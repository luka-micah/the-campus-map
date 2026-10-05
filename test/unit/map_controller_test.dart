import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/data/campus_repository.dart';
import 'package:the_campus_map/features/map/location_service.dart';
import 'package:the_campus_map/features/map/map_controller.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCampusRepository extends Mock implements CampusRepository {}

class MockLocationService extends Mock implements LocationService {}

class MockGoogleMapController extends Mock implements GoogleMapController {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

LocationModel _loc(String id, String name) => LocationModel(
      id: id,
      name: name,
      department: '',
      lat: 7.0,
      lng: 5.0,
      hours: '',
      createdAt: DateTime(2024),
    );

// ---------------------------------------------------------------------------
// Tests — Requirement 14: Offline and Error Resilience (map side)
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  // mocktail needs a valid CameraUpdate instance for any() matchers.
  setUpAll(() => registerFallbackValue(CameraUpdate.zoomIn()));

  late MockCampusRepository repo;
  late MockLocationService locationService;
  late MapController sut;

  setUp(() {
    repo = MockCampusRepository();
    locationService = MockLocationService();
    sut = MapController(
      campusRepository: repo,
      locationService: locationService,
      routingService: RoutingService(),
    );
  });

  group('Requirement 14.1: cached data shows outdated banner', () {
    test('offline cache served without throwing still raises the banner',
        () async {
      // SupabaseCampusRepository swallows the network error internally and
      // returns cache: no throw, but the offline flag is set.
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.isOfflineMode).thenReturn(true);

      await sut.fetchLocations();

      // 14.1: markers display AND the outdated-data banner shows.
      expect(sut.locations.map((l) => l.id).toList(), ['a']);
      expect(sut.isOfflineMode.value, isTrue);
      expect(sut.hasFetchError.value, isFalse);
    });

    test('live data clears both banners', () async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.isOfflineMode).thenReturn(false);

      await sut.fetchLocations();

      expect(sut.locations, hasLength(1));
      expect(sut.isOfflineMode.value, isFalse);
      expect(sut.hasFetchError.value, isFalse);
    });
  });

  group('Requirement 14.2: no cache shows error with retry', () {
    test('throw with nothing cached sets the error state', () async {
      when(() => repo.fetchLocations()).thenThrow(Exception('offline'));
      when(() => repo.isOfflineMode).thenReturn(true);

      await sut.fetchLocations();

      // 14.2: informative error + retry option (view binds Retry to
      // fetchLocations), no crash, markers stay empty.
      expect(sut.locations, isEmpty);
      expect(sut.hasFetchError.value, isTrue);
    });

    test('retry succeeds once the network returns', () async {
      when(() => repo.fetchLocations()).thenThrow(Exception('offline'));
      when(() => repo.isOfflineMode).thenReturn(true);
      await sut.fetchLocations();
      expect(sut.hasFetchError.value, isTrue);

      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.isOfflineMode).thenReturn(false);
      await sut.fetchLocations();

      expect(sut.hasFetchError.value, isFalse);
      expect(sut.locations, hasLength(1));
    });
  });

  group('Requirement 12.1: live marker updates without restart', () {
    late StreamController<List<LocationModel>> locationsEvents;

    setUp(() {
      locationsEvents = StreamController<List<LocationModel>>.broadcast();
      addTearDown(locationsEvents.close);
      when(() => repo.locationsStream())
          .thenAnswer((_) => locationsEvents.stream);
      // Stay in browse-only mode: no position stream involved.
      when(() => locationService.hasPermission).thenReturn(false.obs);
    });

    test('insert event refreshes markers in place', () async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.isOfflineMode).thenReturn(false);
      await sut.fetchLocations();
      expect(sut.locations.map((l) => l.id).toList(), ['a']);

      sut.subscribeToRealtimeUpdates();

      // Admin inserts a location elsewhere: realtime fires, controller
      // re-fetches, markers update with no restart.
      when(() => repo.fetchLocations()).thenAnswer(
        (_) async => [_loc('a', 'Alpha'), _loc('b', 'Beta')],
      );
      locationsEvents.add([_loc('a', 'Alpha'), _loc('b', 'Beta')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sut.locations.map((l) => l.id).toList(), ['a', 'b']);
      expect(sut.hasFetchError.value, isFalse);
    });

    test('delete event removes the marker in place', () async {
      when(() => repo.fetchLocations()).thenAnswer(
        (_) async => [_loc('a', 'Alpha'), _loc('b', 'Beta')],
      );
      when(() => repo.isOfflineMode).thenReturn(false);
      await sut.fetchLocations();
      expect(sut.locations, hasLength(2));

      sut.subscribeToRealtimeUpdates();

      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      locationsEvents.add([_loc('a', 'Alpha')]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(sut.locations.map((l) => l.id).toList(), ['a']);
    });
  });

  group('Requirement 13.4: grant after denial resumes tracking', () {
    test('refreshLocation after grant starts GPS without a restart',
        () async {
      final permission = false.obs;
      when(() => locationService.hasPermission).thenReturn(permission);
      when(() => locationService.requestPermission())
          .thenAnswer((_) async {
        permission.value = true;
      });
      when(() => locationService.getCurrentPosition()).thenAnswer(
        (_) async => const LatLng(7.0, 5.0),
      );
      when(() => locationService.positionStream)
          .thenAnswer((_) => Stream<Position>.empty());
      when(() => locationService.hasSignal)
          .thenAnswer((_) => Stream<bool>.empty());

      expect(sut.userPosition.value, isNull);
      await sut.refreshLocation();

      expect(permission.value, isTrue);
      expect(sut.userPosition.value, const LatLng(7.0, 5.0));
    });
  });

  group('Satellite map-type switcher', () {
    test('defaults to standard map', () {
      expect(sut.mapType.value, MapType.normal);
    });

    test('cycles normal → satellite → hybrid → normal', () {
      sut.cycleMapType();
      expect(sut.mapType.value, MapType.satellite);

      sut.cycleMapType();
      expect(sut.mapType.value, MapType.hybrid);

      sut.cycleMapType();
      expect(sut.mapType.value, MapType.normal);
    });

    test('tooltip names the mode tapping switches to', () {
      expect(sut.nextMapTypeLabel, 'satellite');
      sut.cycleMapType();
      expect(sut.nextMapTypeLabel, 'hybrid');
      sut.cycleMapType();
      expect(sut.nextMapTypeLabel, 'standard');
    });
  });

  group('2D/3D perspective toggle', () {
    late MockGoogleMapController maps;

    setUp(() {
      maps = MockGoogleMapController();
      when(() => maps.animateCamera(any())).thenAnswer((_) async {});
    });

    test('toggle flips mode and animates the camera', () async {
      sut.onMapCreated(maps);
      expect(sut.is3DMode.value, isFalse);

      await sut.toggle3DMode();
      expect(sut.is3DMode.value, isTrue);

      await sut.toggle3DMode();
      expect(sut.is3DMode.value, isFalse);

      // Single terminal verification: mocktail marks matched invocations
      // as verified, so an intermediate verify would skew this count.
      verify(() => maps.animateCamera(any())).called(2);
    });

    test('toggle before the map exists keeps state, applies on creation',
        () async {
      await sut.set3DMode(true);
      expect(sut.is3DMode.value, isTrue);
      verifyNever(() => maps.animateCamera(any()));

      sut.onMapCreated(maps);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(() => maps.animateCamera(any())).called(1);
    });

    test('onCameraMove tracks the viewpoint preserved by the toggle',
        () async {
      sut.onMapCreated(maps);
      sut.onCameraMove(
        const CameraPosition(target: LatLng(7.1, 5.2), zoom: 17),
      );

      expect(sut.mapCameraTarget.value, const LatLng(7.1, 5.2));
      await sut.set3DMode(true);
      verify(() => maps.animateCamera(any())).called(1);
    });
  });

  group('Destination search field', () {
    LocationModel loc(String id, String name) => LocationModel(
          id: id,
          name: name,
          department: 'Dept',
          lat: 7.0,
          lng: 5.0,
          hours: '',
          createdAt: DateTime(2024),
        );

    setUp(() {
      sut.locations.value = [
        loc('1', 'Main Library'),
        loc('2', 'Science Library'),
        loc('3', 'Admin Block'),
      ];
    });

    test('partial query matches case-insensitively', () {
      sut.search('library');

      expect(sut.searchResults.map((l) => l.id).toList(), ['1', '2']);
    });

    test('mixed-case query matches', () {
      sut.search('ADMIN');

      expect(sut.searchResults.map((l) => l.id).toList(), ['3']);
    });

    test('no match yields an empty result list', () {
      sut.search('stadium');

      expect(sut.searchResults, isEmpty);
      expect(sut.searchQuery.value, 'stadium');
    });

    test('empty query clears results', () {
      sut.search('library');
      expect(sut.searchResults, hasLength(2));

      sut.search('   ');
      expect(sut.searchResults, isEmpty);
    });

    test('clearSearch resets query and results', () {
      sut.search('library');
      sut.clearSearch();

      expect(sut.searchQuery.value, isEmpty);
      expect(sut.searchResults, isEmpty);
    });

    test('fresh fetch re-applies the active search', () async {
      when(() => repo.fetchLocations()).thenAnswer(
        (_) async => [loc('1', 'Main Library')],
      );
      when(() => repo.isOfflineMode).thenReturn(false);

      sut.search('library');
      await sut.fetchLocations();

      expect(sut.searchResults.map((l) => l.id).toList(), ['1']);
    });
  });
}
