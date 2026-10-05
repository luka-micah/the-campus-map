import 'dart:async' as async;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/models.dart';
import '../../data/campus_repository.dart';
import '../../routing/routing_service.dart';
import '../map/location_service.dart';
import '../voice/voice_controller.dart';

class NavigationController extends GetxController {
  NavigationController({
    required CampusRepository campusRepository,
    required LocationService locationService,
    required VoiceController voiceController,
    required RoutingService routingService,
  })  : _campusRepository = campusRepository,
        _locationService = locationService,
        _voiceController = voiceController,
        _routingService = routingService;

  final CampusRepository _campusRepository;
  final LocationService _locationService;
  final VoiceController _voiceController;
  final RoutingService _routingService;

  final activeRoute = Rx<RouteModel?>(null);
  final currentStepIndex = 0.obs;
  final remainingDistance = 0.0.obs;
  final isNavigating = false.obs;
  final isRerouting = false.obs;
  final hasGPSSignal = true.obs;

  /// Last route failure message (5.4). Observed by [NavigationView] banner
  /// and announced via snackbar + TTS in [_failRoute]. Cleared whenever a
  /// new route computation starts or succeeds.
  final routeErrorMessage = ''.obs;

  /// True when navigation was blocked for lack of location permission (13.3).
  /// Drives a dedicated banner with a link to the device settings.
  final needsLocationPermission = false.obs;

  async.StreamSubscription? _positionSubscription;
  async.StreamSubscription<bool>? _signalSubscription;

  /// Last known navigation camera target (via [onNavigationCameraMove]),
  /// so tilt changes preserve the user's viewpoint.
  final Rx<LatLng?> navCameraTarget = Rx<LatLng?>(null);

  final async.Completer<GoogleMapController> _navMapCompleter =
      async.Completer<GoogleMapController>();

  /// Whether live GPS callbacks are currently being received.
  bool get isTracking => _positionSubscription != null;

  /// Current location-permission state (13.x). Exposed as a getter so the
  /// gate below reads one place.
  bool get locationServiceHasPermission =>
      _locationService.hasPermission.value;

  /// Opens the OS app-settings screen (13.3 settings link).
  Future<void> openLocationSettings() =>
      _locationService.openAppSettings();

  @override
  void onInit() {
    super.onInit();
    _setupWorkers();
    _subscribeToLocation();
  }

  @override
  void onReady() {
    super.onReady();
    // Entry via map "Navigate" button or voice search passes the destination
    // id as route arguments, so the screen's own controller instance (with
    // its binding-provided services) performs the computation — no
    // cross-instance state split.
    final args = Get.arguments;
    if (args is String && args.isNotEmpty) {
      startNavigationTo(args);
    } else if (args is Map && args['destinationId'] is String) {
      startNavigationTo(args['destinationId'] as String);
    }
  }

  @override
  void onClose() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _signalSubscription?.cancel();
    _signalSubscription = null;
    super.onClose();
  }

  /// Called by the navigation GoogleMap widget once the platform view is
  /// ready. The route may already be computed (normal entry flow), in which
  /// case the tilted chase view is applied immediately.
  void onNavigationMapCreated(GoogleMapController controller) {
    if (_navMapCompleter.isCompleted) return;
    _navMapCompleter.complete(controller);
    if (isNavigating.value && activeRoute.value != null) {
      async.unawaited(_applyNavCamera(tilted: true));
    }
  }

  /// Tracks the navigation camera so tilt changes keep the viewpoint.
  void onNavigationCameraMove(CameraPosition position) {
    navCameraTarget.value = position.target;
  }

  /// Tilts (or flattens) the navigation camera. No-ops until the platform
  /// map exists; the target falls back to the destination, then campus.
  Future<void> _applyNavCamera({required bool tilted}) {
    if (tilted && activeRoute.value == null) return Future.value();
    if (!_navMapCompleter.isCompleted) return Future.value();
    final route = activeRoute.value;
    final target = navCameraTarget.value ??
        (route != null
            ? LatLng(route.destination.lat, route.destination.lng)
            : const LatLng(7.5, 5.5));
    return _animateNavCamera(target, tilted);
  }

  Future<void> _animateNavCamera(LatLng target, bool tilted) async {
    try {
      final map = await _navMapCompleter.future;
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: tilted ? 18 : 16,
            tilt: tilted ? 60 : 0,
          ),
        ),
      );
    } catch (_) {
      // Camera animation is best-effort (disposed view, missing tiles).
    }
  }

  void _setupWorkers() {
    ever(currentStepIndex, (int index) {
      if (activeRoute.value != null && index < activeRoute.value!.turnInstructions.length) {
        _voiceController.speak(activeRoute.value!.turnInstructions[index]);
      }
    });

    ever(hasGPSSignal, (bool hasSignal) {
      if (!hasSignal && isNavigating.value) {
        Get.snackbar('GPS Signal Lost', 'Navigation paused until signal is restored');
      }
    });

    ever(routeErrorMessage, (String message) {
      if (message.isNotEmpty) Get.snackbar('Navigation', message);
    });

    ever(_voiceController.isMuted, (bool muted) {
      // 9.6: unmuting resumes spoken instructions from the current step.
      if (!muted &&
          isNavigating.value &&
          activeRoute.value != null &&
          currentStepIndex.value <
              activeRoute.value!.turnInstructions.length) {
        _voiceController.speak(
          activeRoute.value!.turnInstructions[currentStepIndex.value],
        );
      }
    });
  }

  void _subscribeToLocation() {
    if (_positionSubscription != null) return;
    _positionSubscription = _locationService.positionStream.listen(
      (position) {
        final latLng = LatLng(position.latitude, position.longitude);
        onPositionUpdate(latLng);
      },
      onError: (error) {
        hasGPSSignal.value = false;
      },
    );
    // 14.4: the 15-second no-fix timeout in LocationService.hasSignal drives
    // the GPS-lost banner (via the ever worker) and pauses route tracking
    // in onPositionUpdate until fixes resume.
    _signalSubscription ??= _locationService.hasSignal.listen(
      (signal) {
        hasGPSSignal.value = signal;
      },
      onError: (_) {
        hasGPSSignal.value = false;
      },
    );
  }

  Future<void> _stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _signalSubscription?.cancel();
    _signalSubscription = null;
  }

  /// Starts navigation to the location with [locationId], resolving the
  /// [LocationModel] from the repository first. This is the entry point for
  /// callers that only know the destination id (map "Navigate" button, voice
  /// search): they navigate to the `/navigation` route with the id as
  /// arguments and [onReady] delegates here.
  Future<void> startNavigationTo(String locationId) async {
    routeErrorMessage.value = '';
    if (!await _ensureGraphReady()) {
      _failRoute('Map data is not ready yet. Please try again.');
      return;
    }
    List<LocationModel> locations;
    try {
      locations = await _campusRepository.fetchLocations();
    } catch (_) {
      _failRoute('Could not load campus map data.');
      return;
    }
    final destination = locations.firstWhereOrNull((l) => l.id == locationId);
    if (destination == null) {
      _failRoute('Destination not found on map.');
      return;
    }
    await startNavigation(destination);
  }

  /// Builds the routing graph from the repository when this instance's
  /// [RoutingService] has no nodes yet. Each binding creates its own service
  /// instances, so the navigation screen cannot assume the graph built at
  /// startup is visible here. Returns false when data is unavailable.
  Future<bool> _ensureGraphReady() async {
    if (_routingService.graphNodes.isNotEmpty) return true;
    try {
      final locations = await _campusRepository.fetchLocations();
      final edges = await _campusRepository.fetchEdges();
      _routingService.buildGraph(locations, edges);
      return _routingService.graphNodes.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> startNavigation(LocationModel destination) async {
    routeErrorMessage.value = '';
    needsLocationPermission.value = false;
    if (!await _ensureGraphReady()) {
      _failRoute('Map data is not ready yet. Please try again.');
      return;
    }
    // 13.1/13.4: permission is requested before any GPS read; a grant
    // after an earlier denial proceeds immediately without a restart.
    if (!locationServiceHasPermission) {
      await _locationService.requestPermission();
    }
    if (!locationServiceHasPermission) {
      // 13.3: no silent fallback navigation — explain and link settings.
      needsLocationPermission.value = true;
      routeErrorMessage.value =
          'Live navigation is unavailable without location access.';
      _voiceController.speak(
        'Live navigation is unavailable without location access. '
        'Please grant permission in the system settings.',
      );
      isNavigating.value = false;
      isRerouting.value = false;
      activeRoute.value = null;
      currentStepIndex.value = 0;
      remainingDistance.value = 0.0;
      return;
    }
    // (Re)subscribe: a previous cancelNavigation stops GPS callbacks (6.5).
    _subscribeToLocation();
    isNavigating.value = true;
    isRerouting.value = false;
    currentStepIndex.value = 0;

    // Resolve the user's GPS position to the nearest graph node (5.1, 5.2).
    // nearestNode throws StateError on an empty graph (data not loaded yet).
    late final GraphNode originNode;
    late final LatLng currentPosition;
    try {
      currentPosition = await _locationService.getCurrentPosition();
      originNode = _routingService.nearestNode(currentPosition);
    } on StateError {
      _failRoute('Map data is not ready yet. Please try again.');
      return;
    } catch (_) {
      _failRoute('Could not determine your current position.');
      return;
    }

    final destNode = _routingService.graphNodes[destination.id];
    if (destNode == null) {
      _failRoute('Destination not found on map.');
      return;
    }

    // Async variant honours Requirement 4.5: requests arriving mid-rebuild
    // are queued and answered from the fresh graph.
    final route = await _routingService.computeRouteAsync(originNode, destNode);
    if (route == null) {
      // No path (5.4): RoutingService signals absence with null; the
      // controller detects it independently here and shows a message.
      _failRoute('No navigable path found.');
      return;
    }

    activeRoute.value = route;
    _updateRemainingDistance(currentPosition);
    needsLocationPermission.value = false;
    // Tilted 3D chase view for active guidance (no-op until the map exists).
    navCameraTarget.value = currentPosition;
    async.unawaited(_applyNavCamera(tilted: true));
    if (route.turnInstructions.isEmpty) {
      // Single-node route: the user is already at the destination.
      _arriveAtDestination();
      return;
    }
    _voiceController.speak(route.turnInstructions.first);
  }

  /// Records a route failure visibly ([routeErrorMessage] banner + snackbar
  /// via the worker in [_setupWorkers]) and audibly (TTS), then resets
  /// navigation state (5.4). The user stays on the current screen so the
  /// message remains visible.
  void _failRoute(String message) {
    isNavigating.value = false;
    isRerouting.value = false;
    activeRoute.value = null;
    currentStepIndex.value = 0;
    remainingDistance.value = 0.0;
    routeErrorMessage.value = message;
    _voiceController.speak(message);
  }

  void onPositionUpdate(LatLng position) {
    if (!isNavigating.value || activeRoute.value == null) return;

    // 14.4: GPS signal lost → keep the banner up and pause all route
    // tracking (deviation, reroute, steps, distance) until fixes resume.
    // hasSignal re-emits true with the next fix; at most one stale fix is
    // dropped on the transition.
    if (!hasGPSSignal.value) return;
    hasGPSSignal.value = true;

    if (_hasDeviated(position, _getPolylinePoints())) {
      triggerReroute(position);
      return;
    }

    _checkStepAdvance(position);
    _updateRemainingDistance(position);
  }

  Future<void> triggerReroute(LatLng currentPosition) async {
    if (!isNavigating.value || activeRoute.value == null) return;
    // A reroute is already in flight: retain the previous route until it
    // completes rather than stacking overlapping computations (7.5).
    if (isRerouting.value) return;
    isRerouting.value = true;

    _voiceController.speak('Rerouting...');

    final destNode = activeRoute.value!.destination;
    late final GraphNode originNode;
    try {
      originNode = _routingService.nearestNode(currentPosition);
    } on StateError {
      _voiceController.speak('Reroute failed. Keeping previous route.');
      routeErrorMessage.value = 'Reroute failed. Keeping previous route.';
      isRerouting.value = false;
      return;
    }

    final newRoute = await _routingService.computeRouteAsync(originNode, destNode);
    if (newRoute == null) {
      // Retain the previous route and say + show why (7.5). The banner
      // clears on the next successful reroute, cancel, or new navigation.
      _voiceController.speak('Reroute failed. Keeping previous route.');
      routeErrorMessage.value = 'Reroute failed. Keeping previous route.';
      isRerouting.value = false;
      return;
    }

    routeErrorMessage.value = '';
    activeRoute.value = newRoute;
    currentStepIndex.value = 0;
    isRerouting.value = false;
    // Keep the tilted chase view centred on the new origin.
    navCameraTarget.value = currentPosition;
    async.unawaited(_applyNavCamera(tilted: true));
    if (newRoute.turnInstructions.isEmpty) {
      _arriveAtDestination();
      return;
    }
    _voiceController.speak(newRoute.turnInstructions.first);
  }

  Future<void> cancelNavigation() async {
    // Flatten back to top-down 2D while the destination is still known.
    await _applyNavCamera(tilted: false);
    routeErrorMessage.value = '';
    needsLocationPermission.value = false;
    // Stop GPS tracking callbacks and clear the route polyline (6.5).
    await _stopTracking();
    isNavigating.value = false;
    isRerouting.value = false;
    activeRoute.value = null;
    currentStepIndex.value = 0;
    remainingDistance.value = 0.0;
    _voiceController.stopListening();
    Get.offAllNamed('/map');
  }

  bool _hasDeviated(LatLng position, List<LatLng> polyline) {
    if (polyline.length < 2) return false;

    double minDistance = double.infinity;

    for (int i = 0; i < polyline.length - 1; i++) {
      final a = polyline[i];
      final b = polyline[i + 1];
      final dist = _perpendicularHaversineDistance(position, a, b);
      if (dist < minDistance) minDistance = dist;
    }

    return minDistance > 30.0;
  }

  void _checkStepAdvance(LatLng position) {
    if (activeRoute.value == null) return;

    final route = activeRoute.value!;

    // Arrival takes precedence: destination reached within a 15 m radius
    // marks the route complete, even mid-sequence (6.4).
    final destination = route.destination;
    final distanceToDestination = RoutingService.haversineMeters(
      position.latitude,
      position.longitude,
      destination.lat,
      destination.lng,
    );
    if (distanceToDestination < 15.0) {
      currentStepIndex.value = route.nodes.length - 1;
      _arriveAtDestination();
      return;
    }

    if (currentStepIndex.value >= route.nodes.length - 1) return;

    final nextNode = route.nodes[currentStepIndex.value + 1];
    final distanceToNext = RoutingService.haversineMeters(
      position.latitude,
      position.longitude,
      nextNode.lat,
      nextNode.lng,
    );

    if (distanceToNext < 10.0) {
      currentStepIndex.value++;
      if (currentStepIndex.value >= route.nodes.length - 1) {
        _arriveAtDestination();
      }
    }
  }

  void _arriveAtDestination() {
    isNavigating.value = false;
    _voiceController.speak('You have arrived at ${activeRoute.value!.destination.name}.');
    // Settle back to a top-down view of the destination.
    async.unawaited(_applyNavCamera(tilted: false));
    // No overlay in headless/unit-test contexts: arrival state + TTS above
    // are the contract; the dialog is presentation only.
    if (Get.overlayContext == null) return;
    Get.dialog(
      AlertDialog(
        title: const Text('Arrived'),
        content: Text('You have reached ${activeRoute.value!.destination.name}'),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
              cancelNavigation();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _updateRemainingDistance([LatLng? currentPosition]) {
    if (activeRoute.value == null) {
      remainingDistance.value = 0.0;
      return;
    }

    final nodes = activeRoute.value!.nodes;
    if (currentStepIndex.value >= nodes.length - 1) {
      remainingDistance.value = 0.0;
      return;
    }

    // Estimated remaining distance (6.3): live GPS position to the next
    // waypoint, plus straight-line legs for the rest of the route.
    // Recomputed on every GPS update so the displayed value tracks movement,
    // not just step advances.
    final LatLng from;
    if (currentPosition != null) {
      from = currentPosition;
    } else {
      final anchor = nodes[currentStepIndex.value];
      from = LatLng(anchor.lat, anchor.lng);
    }
    double total = RoutingService.haversineMeters(
      from.latitude,
      from.longitude,
      nodes[currentStepIndex.value + 1].lat,
      nodes[currentStepIndex.value + 1].lng,
    );
    for (int i = currentStepIndex.value + 1; i < nodes.length - 1; i++) {
      final from = nodes[i];
      final to = nodes[i + 1];
      total += RoutingService.haversineMeters(
        from.lat,
        from.lng,
        to.lat,
        to.lng,
      );
    }
    remainingDistance.value = total;
  }

  List<LatLng> _getPolylinePoints() {
    if (activeRoute.value == null) return [];
    return activeRoute.value!.nodes
        .map((n) => LatLng(n.lat, n.lng))
        .toList();
  }

  /// Shortest distance in metres from [p] to the segment [a]→[b].
  ///
  /// Uses a local equirectangular projection around the segment (accurate to
  /// centimetres at campus scale): project P onto the line AB, clamp the
  /// projection to the segment, and measure to the clamped point. Points
  /// beyond the endpoints measure to the nearer endpoint, so walking past a
  /// waypoint never counts as a deviation from its segment.
  static double _perpendicularHaversineDistance(LatLng p, LatLng a, LatLng b) {
    const double earthRadiusMeters = 6371000.0;
    final double latRefRad =
        (a.latitude + b.latitude) / 2 * math.pi / 180;
    final double cosRef = math.cos(latRefRad);

    double toX(LatLng q) =>
        (q.longitude - a.longitude) * math.pi / 180 * earthRadiusMeters * cosRef;
    double toY(LatLng q) =>
        (q.latitude - a.latitude) * math.pi / 180 * earthRadiusMeters;

    final double vx = toX(b);
    final double vy = toY(b);
    final double wx = toX(p);
    final double wy = toY(p);

    final double lenSquared = vx * vx + vy * vy;
    if (lenSquared == 0) {
      // Degenerate zero-length segment: distance to the shared endpoint.
      return math.sqrt(wx * wx + wy * wy);
    }

    double t = (wx * vx + wy * vy) / lenSquared;
    t = t.clamp(0.0, 1.0);

    final double dx = wx - t * vx;
    final double dy = wy - t * vy;
    return math.sqrt(dx * dx + dy * dy);
  }
}