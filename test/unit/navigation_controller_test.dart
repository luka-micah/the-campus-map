import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';import 'package:mocktail/mocktail.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/data/campus_repository.dart';
import 'package:the_campus_map/features/map/location_service.dart';
import 'package:the_campus_map/features/navigation/navigation_controller.dart';
import 'package:the_campus_map/features/voice/voice_controller.dart';
import 'package:the_campus_map/features/voice/voice_service.dart';
import 'package:the_campus_map/routing/routing_service.dart';
import 'package:the_campus_map/core/models/edge_model.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCampusRepository extends Mock implements CampusRepository {}

class MockLocationService extends Mock implements LocationService {}

class MockVoiceController extends Mock implements VoiceController {}

class MockNavMapController extends Mock implements GoogleMapController {}

/// Hand-written voice double used where mocktail cannot observe calls made
/// from inside GetX worker callbacks. Records spoken utterances directly.
class FakeVoiceController extends Fake implements VoiceController {
  FakeVoiceController(this.service);

  final FakeVoiceService2 service;

  @override
  final isMuted = false.obs;

  @override
  Future<void> speak(String text) async {
    if (isMuted.value) return;
    if (service.isSpeaking) return;
    await service.speak(text);
  }

  @override
  Future<void> stopListening() async {}
}

/// Minimal voice-service double backing [FakeVoiceController].
class FakeVoiceService2 implements VoiceService {
  bool speaking = false;
  final spoken = <String>[];
  void Function()? _onComplete;

  @override
  bool get isSpeaking => speaking;

  @override
  void Function()? get onComplete => _onComplete;

  @override
  set onComplete(void Function()? cb) => _onComplete = cb;

  @override
  Future<bool> hasMicPermission() async => true;

  @override
  Future<bool> requestMicPermission() async => true;

  @override
  Future<void> startListening(void Function(String p1) onResult) async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

LocationModel _loc(String id, String name, {double lat = 0.0, double lng = 0.0}) =>
    LocationModel(
      id: id,
      name: name,
      department: '',
      lat: lat,
      lng: lng,
      hours: '',
      createdAt: DateTime(2024),
    );

EdgeModel _edge(String id, String from, String to, double dist) => EdgeModel(
      id: id,
      fromLocationId: from,
      toLocationId: to,
      distanceMeters: dist,
    );

/// A ─100m─ B ─150m─ C chain used across tests (distinct coordinates so
/// Haversine-based remaining-distance estimates are non-zero).
List<LocationModel> get _chainLocations => [
      _loc('a', 'Alpha', lat: 7.0, lng: 5.0),
      _loc('b', 'Beta', lat: 7.001, lng: 5.0),
      _loc('c', 'Gamma', lat: 7.002, lng: 5.0),
    ];

List<EdgeModel> get _chainEdges =>
    [_edge('e1', 'a', 'b', 100.0), _edge('e2', 'b', 'c', 150.0)];

// ---------------------------------------------------------------------------
// Tests — Requirement 5: Route Computation
// ---------------------------------------------------------------------------

void main() {
  // Navigation paths touch GetX navigation/dialog APIs (cancel → /map,
  // arrival confirmation). Test mode + an initialized binding keep those
  // calls safe no-ops in headless unit tests.
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  // mocktail needs a valid CameraUpdate instance for any() matchers.
  setUpAll(() => registerFallbackValue(CameraUpdate.zoomIn()));

  late MockCampusRepository repo;
  late MockLocationService locationService;
  late MockVoiceController voice;
  late RoutingService routing;
  late NavigationController sut;

  setUp(() {
    repo = MockCampusRepository();
    locationService = MockLocationService();
    voice = MockVoiceController();
    routing = RoutingService();

    when(() => voice.speak(any())).thenAnswer((_) async {});
    when(() => voice.stopListening()).thenAnswer((_) async {});
    // Workers registered in onInit observe this; tests needing transitions
    // re-stub it with their own RxBool below.
    when(() => voice.isMuted).thenReturn(false.obs);
    when(() => locationService.positionStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => locationService.hasSignal)
        .thenAnswer((_) => Stream<bool>.empty());
    // startNavigation gates on permission (13.x): default to granted so
    // existing route tests exercise routing, not the gate. Permission
    // tests below re-stub this with their own RxBool.
    when(() => locationService.hasPermission).thenReturn(true.obs);

    sut = NavigationController(
      campusRepository: repo,
      locationService: locationService,
      voiceController: voice,
      routingService: routing,
    );
  });

  group('startNavigation', () {
    test('happy path sets activeRoute with shortest path and announces it',
        () async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));

      await sut.startNavigation(_chainLocations.last);

      expect(sut.routeErrorMessage.value, isEmpty);
      expect(sut.activeRoute.value, isNotNull);
      expect(
        sut.activeRoute.value!.nodes.map((n) => n.id).toList(),
        ['a', 'b', 'c'],
      );
      expect(sut.activeRoute.value!.totalDistanceMeters, closeTo(250.0, 1e-9));
      expect(sut.isNavigating.value, isTrue);
      expect(sut.remainingDistance.value, greaterThan(0));
      verify(() => voice.speak('Head towards Beta')).called(1);
    });

    test('disconnected graph reports "No navigable path found" visibly',
        () async {
      routing.buildGraph(_chainLocations, []);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));

      await sut.startNavigation(_chainLocations.last);

      // 5.4: independently detected + visible message (not TTS-only).
      expect(sut.routeErrorMessage.value, 'No navigable path found.');
      expect(sut.activeRoute.value, isNull);
      expect(sut.isNavigating.value, isFalse);
      verify(() => voice.speak('No navigable path found.')).called(1);
    });

    test('empty graph reports map data not ready instead of throwing',
        () async {
      when(() => repo.fetchLocations()).thenAnswer((_) async => <LocationModel>[]);
      when(() => repo.fetchEdges()).thenAnswer((_) async => <EdgeModel>[]);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));

      await sut.startNavigation(_chainLocations.first);

      expect(sut.routeErrorMessage.value, isNotEmpty);
      expect(sut.activeRoute.value, isNull);
      expect(sut.isNavigating.value, isFalse);
    });

    test('uses queued async route so admin rebuilds cannot race computation',
        () async {
      routing.buildGraph(_chainLocations, _chainEdges);
      routing.rebuildPending = true; // simulate an incoming Realtime event
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));

      // Drain the (simulated) rebuild on the next microtask, then the queued
      // request must resolve against the fresh graph.
      Future<void>.delayed(Duration.zero, () {
        routing.buildGraph(_chainLocations, _chainEdges);
      });

      await sut.startNavigation(_chainLocations.last);

      expect(sut.activeRoute.value, isNotNull);
      expect(sut.activeRoute.value!.totalDistanceMeters, closeTo(250.0, 1e-9));
    });
  });

  group('startNavigationTo', () {
    test('resolves the destination id and navigates', () async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => List.of(_chainLocations));
      when(() => repo.fetchEdges()).thenAnswer((_) async => List.of(_chainEdges));
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));

      await sut.startNavigationTo('c');

      expect(sut.routeErrorMessage.value, isEmpty);
      expect(sut.activeRoute.value, isNotNull);
      expect(sut.activeRoute.value!.destination.id, 'c');
      expect(sut.isNavigating.value, isTrue);
    });

    test('unknown id reports "Destination not found on map"', () async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => List.of(_chainLocations));
      when(() => repo.fetchEdges()).thenAnswer((_) async => List.of(_chainEdges));

      await sut.startNavigationTo('ghost');

      expect(sut.routeErrorMessage.value, 'Destination not found on map.');
      expect(sut.activeRoute.value, isNull);
      expect(sut.isNavigating.value, isFalse);
    });
  });

  group('Requirement 6: turn-by-turn navigation', () {
    Future<void> startHappyPath() async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
      await sut.startNavigation(_chainLocations.last);
      expect(sut.isNavigating.value, isTrue);
    }

    test('current instruction is the first step while navigating', () async {
      await startHappyPath();

      expect(sut.activeRoute.value, isNotNull);
      expect(sut.currentStepIndex.value, 0);
      expect(
        sut.activeRoute.value!.turnInstructions.first,
        'Head towards Beta',
      );
    });

    test('passing a waypoint auto-advances to the next instruction',
        () async {
      // Workers (step-change → TTS) are wired in onInit in production.
      sut.onInit();
      addTearDown(sut.onClose);
      await startHappyPath();

      // GPS fix exactly on node B: on-polyline, within 10 m of next waypoint.
      sut.onPositionUpdate(const LatLng(7.001, 5.0));

      expect(sut.currentStepIndex.value, 1);
      expect(sut.isNavigating.value, isTrue);
      expect(sut.remainingDistance.value, greaterThanOrEqualTo(0));
      verify(() => voice.speak('Head towards Gamma')).called(1);
    });

    test('remaining distance updates with each GPS position change',
        () async {
      await startHappyPath();
      final before = sut.remainingDistance.value;

      sut.onPositionUpdate(const LatLng(7.0005, 5.0));

      expect(sut.remainingDistance.value, lessThan(before));
    });

    test('destination reached within 15 m marks arrival with confirmation',
        () async {
      await startHappyPath();

      // ~11 m short of Gamma: inside the 15 m arrival radius (6.4).
      sut.onPositionUpdate(const LatLng(7.0019, 5.0));

      expect(sut.isNavigating.value, isFalse);
      expect(sut.currentStepIndex.value,
          sut.activeRoute.value!.nodes.length - 1);
      verify(() => voice.speak('You have arrived at Gamma.')).called(1);
    });

    test('cancel clears the route, stops GPS callbacks', () async {
      await startHappyPath();
      expect(sut.isTracking, isTrue);

      await sut.cancelNavigation();

      expect(sut.activeRoute.value, isNull);
      expect(sut.isNavigating.value, isFalse);
      expect(sut.isRerouting.value, isFalse);
      expect(sut.currentStepIndex.value, 0);
      expect(sut.remainingDistance.value, 0.0);
      expect(sut.isTracking, isFalse);
      // Stopped callbacks are inert even if a fix somehow arrives.
      sut.onPositionUpdate(const LatLng(7.001, 5.0));
      expect(sut.activeRoute.value, isNull);
    });
  });

  group('Requirement 7: automatic rerouting on deviation', () {
    Future<void> startHappyPath() async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
      await sut.startNavigation(_chainLocations.last);
      expect(sut.isNavigating.value, isTrue);
    }

    // onPositionUpdate delegates to the async triggerReroute without awaiting
    // it, so tests yield to let the reroute complete.
    Future<void> settleReroute() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('position >30 m off-polyline triggers reroute to a new route',
        () async {
      await startHappyPath();
      final before = sut.activeRoute.value;

      // ~1.1 km east of the polyline: nearest node is A, destination stays C.
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settleReroute();

      // 7.3: active route replaced with a fresh A→B→C computation.
      expect(sut.activeRoute.value, isNot(same(before)));
      expect(
        sut.activeRoute.value!.nodes.map((n) => n.id).toList(),
        ['a', 'b', 'c'],
      );
      expect(sut.currentStepIndex.value, 0);
      expect(sut.isRerouting.value, isFalse);
      expect(sut.routeErrorMessage.value, isEmpty);
      // 7.4: rerouting notification spoken before the new instruction.
      verify(() => voice.speak('Rerouting...')).called(1);
    });

    test('position on the polyline does not trigger a reroute', () async {
      await startHappyPath();
      final before = sut.activeRoute.value;

      // Midpoint of segment A→B: deviation ≈ 0 m.
      sut.onPositionUpdate(const LatLng(7.0005, 5.0));
      await settleReroute();

      expect(sut.activeRoute.value, same(before));
      expect(sut.isRerouting.value, isFalse);
      verifyNever(() => voice.speak('Rerouting...'));
    });

    test('failed reroute shows a message and retains the previous route',
        () async {
      await startHappyPath();
      final before = sut.activeRoute.value;

      // Break the graph, then stray: no path exists from anywhere to C.
      routing.buildGraph(_chainLocations, []);
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settleReroute();

      // 7.5: previous route retained + visible error (not TTS-only).
      expect(sut.activeRoute.value, same(before));
      expect(sut.isRerouting.value, isFalse);
      expect(sut.routeErrorMessage.value,
          'Reroute failed. Keeping previous route.');
      verify(() => voice.speak('Reroute failed. Keeping previous route.'))
          .called(1);
    });

    test('successful reroute clears a previous failure message', () async {
      await startHappyPath();

      routing.buildGraph(_chainLocations, []);
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settleReroute();
      expect(sut.routeErrorMessage.value, isNotEmpty);

      // Admin restores connectivity; straying again now reroutes cleanly.
      routing.buildGraph(_chainLocations, _chainEdges);
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settleReroute();

      expect(sut.routeErrorMessage.value, isEmpty);
      expect(sut.activeRoute.value, isNotNull);
      expect(
        sut.activeRoute.value!.nodes.map((n) => n.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('concurrent deviation during a reroute does not stack reroutes',
        () async {
      await startHappyPath();

      // Hold the rebuild gate shut so the first reroute stays in flight...
      routing.rebuildPending = true;
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      // ...and stray again while it is pending.
      sut.onPositionUpdate(const LatLng(7.0, 5.02));
      routing.buildGraph(_chainLocations, _chainEdges);
      await settleReroute();

      // Exactly one reroute notification: the second trigger was ignored.
      verify(() => voice.speak('Rerouting...')).called(1);
      expect(sut.isRerouting.value, isFalse);
    });
  });

  group('Requirement 14.4: GPS signal loss pauses tracking', () {
    Future<void> startHappyPath() async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
      await sut.startNavigation(_chainLocations.last);
      expect(sut.isNavigating.value, isTrue);
    }

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('deviated fix while signal is lost does not reroute', () async {
      await startHappyPath();
      final before = sut.activeRoute.value;

      // Signal lost: banner up (via worker in production), tracking paused.
      sut.hasGPSSignal.value = false;
      sut.onPositionUpdate(const LatLng(7.0, 5.01)); // ~1.1 km off-polyline
      await settle();

      expect(sut.activeRoute.value, same(before));
      expect(sut.isRerouting.value, isFalse);
      expect(sut.currentStepIndex.value, 0);
      verifyNever(() => voice.speak('Rerouting...'));
    });

    test('tracking resumes once the signal returns', () async {
      await startHappyPath();

      sut.hasGPSSignal.value = false;
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settle();
      verifyNever(() => voice.speak('Rerouting...'));

      // hasSignal re-emits true with the next fix: rerouting unpauses.
      sut.hasGPSSignal.value = true;
      sut.onPositionUpdate(const LatLng(7.0, 5.01));
      await settle();

      verify(() => voice.speak('Rerouting...')).called(1);
      expect(sut.isRerouting.value, isFalse);
      expect(sut.activeRoute.value, isNotNull);
    });
  });

  group('Requirement 9.6: unmute resumes the current step', () {
    // NOTE: mocktail cannot observe mock invocations made from inside GetX
    // worker callbacks in this setup, so this group uses hand-written fakes
    // that record utterances directly. Behaviour under test is identical.
    test('unmuting re-speaks the active turn instruction', () async {
      final voiceService = FakeVoiceService2();
      final fakeVoice = FakeVoiceController(voiceService);
      final nav = NavigationController(
        campusRepository: repo,
        locationService: locationService,
        voiceController: fakeVoice,
        routingService: routing,
      );
      nav.onInit();
      addTearDown(nav.onClose);

      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
      await nav.startNavigation(_chainLocations.last);
      expect(
        voiceService.spoken.where((s) => s == 'Head towards Beta').length,
        1,
      );

      fakeVoice.isMuted.value = true; // mute: nothing new spoken
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        voiceService.spoken.where((s) => s == 'Head towards Gamma').length,
        0,
      );

      fakeVoice.isMuted.value = false; // unmute: resume current step
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        voiceService.spoken.where((s) => s == 'Head towards Beta').length,
        2,
      );
      expect(nav.currentStepIndex.value, 0);
    });
  });

  group('Requirement 13.3: navigation without location permission', () {
    Future<void> buildConnectedGraph() async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
    }

    test('denial blocks navigation with a message and settings flag',
        () async {
      await buildConnectedGraph();
      final permission = false.obs;
      when(() => locationService.hasPermission).thenReturn(permission);
      when(() => locationService.requestPermission())
          .thenAnswer((_) async {});

      await sut.startNavigation(_chainLocations.last);

      // 13.1: the OS prompt is attempted before any GPS read; 13.3: denial
      // explains itself instead of navigating from fallback coordinates.
      verify(() => locationService.requestPermission()).called(1);
      verifyNever(() => locationService.getCurrentPosition());
      expect(sut.needsLocationPermission.value, isTrue);
      expect(
        sut.routeErrorMessage.value,
        'Live navigation is unavailable without location access.',
      );
      expect(sut.activeRoute.value, isNull);
      expect(sut.isNavigating.value, isFalse);
      verify(() => voice.speak(
          'Live navigation is unavailable without location access. '
          'Please grant permission in the system settings.')).called(1);
    });

    test('grant on request proceeds without a restart', () async {
      await buildConnectedGraph();
      final permission = false.obs;
      when(() => locationService.hasPermission).thenReturn(permission);
      when(() => locationService.requestPermission()).thenAnswer((_) async {
        permission.value = true;
      });

      await sut.startNavigation(_chainLocations.last);

      expect(sut.needsLocationPermission.value, isFalse);
      expect(sut.activeRoute.value, isNotNull);
      expect(sut.isNavigating.value, isTrue);
    });

    test('openLocationSettings delegates to the location service', () async {
      when(() => locationService.openAppSettings())
          .thenAnswer((_) async => true);

      await sut.openLocationSettings();

      verify(() => locationService.openAppSettings()).called(1);
    });
  });

  group('triggerReroute', () {
    test('failed reroute keeps the previous route', () async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(0.0, 0.0));
      await sut.startNavigation(_chainLocations.last);
      final previous = sut.activeRoute.value;
      expect(previous, isNotNull);

      // Far-away position on an empty-graph instance cannot occur here;
      // instead simulate failure by moving to a position whose nearest node
      // is isolated: rebuild without edges, then reroute.
      routing.buildGraph(_chainLocations, []);
      await sut.triggerReroute(const LatLng(0.0, 0.0));

      expect(sut.activeRoute.value, same(previous));
      expect(sut.isRerouting.value, isFalse);
      verify(() => voice.speak('Reroute failed. Keeping previous route.'))
          .called(1);
    });
  });

  group('3D navigation camera', () {
    late MockNavMapController maps;

    Future<void> startHappyPath() async {
      routing.buildGraph(_chainLocations, _chainEdges);
      when(() => locationService.getCurrentPosition())
          .thenAnswer((_) async => const LatLng(7.0, 5.0));
      await sut.startNavigation(_chainLocations.last);
      expect(sut.activeRoute.value, isNotNull);
    }

    setUp(() {
      maps = MockNavMapController();
      when(() => maps.animateCamera(any())).thenAnswer((_) async {});
    });

    test('start tilts the camera when the map is already ready', () async {
      sut.onNavigationMapCreated(maps);
      await startHappyPath();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => maps.animateCamera(any())).called(1);
    });

    test('map created after the route still tilts', () async {
      await startHappyPath();
      verifyNever(() => maps.animateCamera(any()));

      sut.onNavigationMapCreated(maps);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      verify(() => maps.animateCamera(any())).called(1);
    });

    test('cancel flattens the camera back to top-down', () async {
      sut.onNavigationMapCreated(maps);
      await startHappyPath();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sut.isNavigating.value, isTrue);

      await sut.cancelNavigation();

      // Once for the tilted start, once for the flatten on cancel.
      verify(() => maps.animateCamera(any())).called(2);
      expect(sut.activeRoute.value, isNull);
    });

    test('camera moves are tracked for tilt preservation', () async {
      sut.onNavigationCameraMove(
        const CameraPosition(target: LatLng(7.1, 5.2), zoom: 17),
      );

      expect(sut.navCameraTarget.value, const LatLng(7.1, 5.2));
    });
  });
}
