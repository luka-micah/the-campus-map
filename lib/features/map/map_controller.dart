import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/campus_repository.dart';
import '../../core/utils/location_search.dart';
import 'location_service.dart';
import '../../core/models/models.dart';
import '../../routing/routing_service.dart';

class MapController extends GetxController {
  final CampusRepository campusRepository;
  final LocationService locationService;
  final RoutingService routingService;

  final RxList<LocationModel> locations = <LocationModel>[].obs;
  final Rx<LatLng?> userPosition = Rx<LatLng?>(null);
  final RxBool hasFetchError = false.obs;
  final RxBool isOfflineMode = false.obs;

  /// 2D/3D toggle state (true = tilted perspective with 3D buildings).
  final RxBool is3DMode = false.obs;

  /// Basemap style, cycled normal → satellite → hybrid by [cycleMapType].
  /// Hybrid (satellite imagery + road/label overlay) is included because bare
  /// satellite hides the building names users navigate by.
  final Rx<MapType> mapType = MapType.normal.obs;

  /// Last known camera target, kept via [onCameraMove] so the 2D/3D toggle
  /// preserves where the user is looking.
  final Rx<LatLng> mapCameraTarget = const LatLng(7.5, 5.5).obs;

  /// Destination search state: the query text and its live matches.
  /// Filtering runs over the already-loaded [locations] (same
  /// case-insensitive partial-match rule as the repository search), so it is
  /// instant and works offline.
  final RxString searchQuery = ''.obs;
  final RxList<LocationModel> searchResults = <LocationModel>[].obs;

  final Completer<GoogleMapController> _mapCompleter =
      Completer<GoogleMapController>();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<LocationModel>>? _realtimeSubscription;
  StreamSubscription<bool>? _signalSubscription;

  MapController({
    required this.campusRepository,
    required this.locationService,
    required this.routingService,
  });

  Future<void> fetchLocations() async {
    try {
      final fetched = await campusRepository.fetchLocations();
      locations.value = fetched;
      // Re-apply the active search to the fresh data.
      search(searchQuery.value);
      // 14.1: the repository serves last-cached data WITHOUT throwing when
      // offline, so success alone cannot clear the banner — mirror its flag.
      // 14.2: only an empty result with nothing to show is an error.
      isOfflineMode.value = campusRepository.isOfflineMode;
      hasFetchError.value = fetched.isEmpty;
    } catch (_) {
      hasFetchError.value = true;
      isOfflineMode.value = campusRepository.isOfflineMode;
    }
  }

  /// Filters the loaded locations by name or department (case-insensitive
  /// partial match, shared with voice search). Voice-style phrasing
  /// ("take me to the library") is stripped, so pasted transcripts work too.
  /// An empty query clears the results and hides the result list.
  void search(String query) {
    searchQuery.value = query;
    if (query.trim().isEmpty) {
      searchResults.clear();
      return;
    }
    searchResults.value = filterLocations(locations, query);
  }

  /// Clears the search field and its results.
  void clearSearch() {
    searchQuery.value = '';
    searchResults.clear();
  }

  void onMarkerTapped(String locationId) {
    final location = locations.firstWhere(
      (loc) => loc.id == locationId,
      orElse: () => LocationModel(
        id: '',
        name: '',
        department: '',
        lat: 0.0,
        lng: 0.0,
        hours: '',
        createdAt: DateTime.now(),
      ),
    );
    if (location.id.isEmpty) return;
    // Details dialog with a Navigate entry point (5.1): the destination id
    // travels as route arguments and the navigation screen's own controller
    // computes the route, avoiding cross-instance state splits.
    Get.dialog(
      AlertDialog(
        title: Text(location.name),
        content: Text('${location.department}\n${location.hours}'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              Get.toNamed('/navigation', arguments: location.id);
            },
            child: const Text('Navigate'),
          ),
        ],
      ),
    );
  }

  void subscribeToRealtimeUpdates() {
    _realtimeSubscription ??=
        campusRepository.locationsStream().listen((updatedLocations) {
      fetchLocations();
    }, onError: (_) {
      // Silently handle stream errors
    });

    _subscribePosition();
  }

  void _subscribePosition() {
    // Position streams require granted permission — otherwise Geolocator
    // throws and the browse-only banner is the correct state.
    if (!locationService.hasPermission.value) return;
    if (_positionSubscription != null) return;

    _signalSubscription ??= locationService.hasSignal.listen((hasSignal) {
      if (!hasSignal) {
        // Handle signal loss
      }
    }, onError: (_) {});

    _positionSubscription =
        locationService.positionStream.listen((position) {
      userPosition.value = LatLng(position.latitude, position.longitude);
    }, onError: (_) {
      // Handle position stream errors silently
    });
  }

  /// Called by GetX when the map screen is shown. Previously nothing ever
  /// called [LocationService.requestPermission], so `hasPermission` stayed
  /// false forever and the "GPS denied — browse-only mode" banner never left.
  @override
  void onReady() {
    super.onReady();
    _init();
  }

  Future<void> _init() async {
    await fetchLocations();
    // Always keep campus data live, even in browse-only mode.
    subscribeToRealtimeUpdates();
    // Trigger the system location prompt, then start GPS if granted.
    await refreshLocation();
  }

  /// Re-request permission and (re)start the position stream. Call again
  /// after the user grants permission in system settings.
  Future<void> refreshLocation() async {
    await locationService.requestPermission();
    if (!locationService.hasPermission.value) return;
    try {
      userPosition.value = await locationService.getCurrentPosition();
    } catch (_) {}
    _subscribePosition();
  }

  /// Called by the GoogleMap widget once the platform view is ready.
  void onMapCreated(GoogleMapController controller) {
    if (_mapCompleter.isCompleted) return;
    _mapCompleter.complete(controller);
    // The initial camera is already top-down 2D; only re-apply a 3D mode
    // that was requested before the map existed.
    if (is3DMode.value) unawaited(_applyMapCamera());
  }

  /// Tracks the camera so the 2D/3D toggle preserves the user's viewpoint.
  void onCameraMove(CameraPosition position) {
    mapCameraTarget.value = position.target;
  }

  /// Flips between top-down 2D and tilted 3D (extruded buildings where
  /// Google has modelled them). Tilt requires street-level zoom to render.
  Future<void> toggle3DMode() => set3DMode(!is3DMode.value);

  static const List<MapType> _mapTypeCycle = [
    MapType.normal,
    MapType.satellite,
    MapType.hybrid,
  ];

  /// Cycles the basemap normal → satellite → hybrid → normal. The view
  /// observes [mapType], so this takes effect on the next frame with no
  /// reload. Satellite tiles need network; offline users keep cached tiles
  /// where available and blank tiles elsewhere (no crash).
  void cycleMapType() {
    final next =
        _mapTypeCycle[( _mapTypeCycle.indexOf(mapType.value) + 1) %
            _mapTypeCycle.length];
    mapType.value = next;
  }

  /// Human label for the layers button tooltip (names the mode tapping
  /// switches *to*, so users always know what comes next).
  String get nextMapTypeLabel {
    final next =
        _mapTypeCycle[( _mapTypeCycle.indexOf(mapType.value) + 1) %
            _mapTypeCycle.length];
    return switch (next) {
      MapType.satellite => 'satellite',
      MapType.hybrid => 'hybrid',
      _ => 'standard',
    };
  }
  Future<void> set3DMode(bool enabled) {
    is3DMode.value = enabled;
    return _applyMapCamera();
  }

  Future<void> _applyMapCamera() {
    // No platform map yet (e.g. toggled before first build): state is kept
    // and applied in onMapCreated.
    if (!_mapCompleter.isCompleted) return Future.value();
    return _animateMapCamera();
  }

  Future<void> _animateMapCamera() async {
    try {
      final map = await _mapCompleter.future;
      final tilted = is3DMode.value;
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: mapCameraTarget.value,
            zoom: tilted ? 18 : 16,
            tilt: tilted ? 60 : 0,
          ),
        ),
      );
    } catch (_) {
      // Camera animation is best-effort (disposed view, missing tiles).
    }
  }

  @override
  void onClose() {
    _positionSubscription?.cancel();
    _realtimeSubscription?.cancel();
    _signalSubscription?.cancel();
    locationService.dispose();
    super.onClose();
  }
}
