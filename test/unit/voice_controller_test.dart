import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/data/campus_repository.dart';
import 'package:the_campus_map/features/voice/voice_controller.dart';
import 'package:the_campus_map/features/voice/voice_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockVoiceService extends Mock implements VoiceService {}

class MockCampusRepository extends Mock implements CampusRepository {}

// ---------------------------------------------------------------------------
// Fixtures & helpers
// ---------------------------------------------------------------------------

LocationModel _loc(String id, String name) => LocationModel(
      id: id,
      name: name,
      department: 'Dept',
      lat: 7.0,
      lng: 5.0,
      hours: '',
      createdAt: DateTime(2024),
    );

/// Stubs startListening to synchronously deliver [heard] to the STT callback,
/// mimicking a completed speech session.
void _hear(MockVoiceService svc, String heard) {
  when(() => svc.startListening(any())).thenAnswer((invocation) async {
    final cb =
        invocation.positionalArguments[0] as void Function(String);
    cb(heard);
  });
}

// ---------------------------------------------------------------------------
// Tests — Requirement 8: Voice Destination Search (STT)
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  late MockVoiceService service;
  late MockCampusRepository repo;
  late VoiceController sut;

  setUp(() {
    service = MockVoiceService();
    repo = MockCampusRepository();
    sut = VoiceController(voiceService: service, campusRepository: repo);

    when(() => service.hasMicPermission()).thenAnswer((_) async => true);
    when(() => service.isSpeaking).thenReturn(false);
    when(() => service.speak(any())).thenAnswer((_) async {});
    when(() => service.stopListening()).thenAnswer((_) async {});
    when(() => service.stop()).thenAnswer((_) async {});
  });

  group('Requirement 8.1/8.2: listening session', () {
    test('activating search starts an STT session and tracks state',
        () async {
      _hear(service, '');
      await sut.startListening();

      verify(() => service.startListening(any())).called(1);
      // Session completes synchronously in the stub: not stuck listening.
      expect(sut.isListening.value, isFalse);
    });

    test('re-entrant activation while listening is ignored', () async {
      sut.isListening.value = true;

      await sut.startListening();

      verifyNever(() => service.startListening(any()));
    });
  });

  group('Requirement 8.3/8.5: result handling', () {
    test('empty speech triggers the no-location retry prompt', () async {
      _hear(service, '   ');

      await sut.startListening();

      verify(() => service.speak('No location found. Please try again.'))
          .called(1);
      verifyNever(() => repo.searchLocations(any()));
      expect(sut.searchMatches, isEmpty);
    });

    test('no match triggers the TTS no-match response', () async {
      _hear(service, 'Nowhere Hall');
      when(() => repo.searchLocations(any())).thenAnswer((_) async => []);

      await sut.startListening();

      verify(() => repo.searchLocations('Nowhere Hall')).called(1);
      verify(() => service.speak('No location found. Please try again.'))
          .called(1);
      expect(sut.searchMatches, isEmpty);
    });

    test('offline search failure announces unavailability', () async {
      _hear(service, 'Library');
      when(() => repo.searchLocations(any()))
          .thenThrow(Exception('offline'));

      await sut.startListening();

      verify(() =>
              service.speak('Search is unavailable while offline. Please try again.'))
          .called(1);
      expect(sut.searchMatches, isEmpty);
    });
  });

  group('Requirement 8.6: single match navigates', () {
    test('exactly one match announces and opens navigation', () async {
      final library = _loc('l1', 'Library');
      _hear(service, 'library');
      when(() => repo.searchLocations(any()))
          .thenAnswer((_) async => [library]);

      await sut.startListening();

      verify(() => service.speak('Navigating to Library.')).called(1);
      expect(sut.searchMatches, isEmpty);
      // Route push (Get.toNamed('/navigation', arguments: 'l1')) needs a
      // running GetMaterialApp, so it is covered by manual/integration
      // testing; the receiving side (onReady → startNavigationTo) is
      // unit-tested in navigation_controller_test.dart.
    });
  });

  group('Requirement 8.7: multiple matches listed for selection', () {
    test('names are spoken and shown on screen', () async {
      _hear(service, 'hall');
      when(() => repo.searchLocations(any())).thenAnswer(
        (_) async => [_loc('h1', 'Alpha Hall'), _loc('h2', 'Beta Hall')],
      );

      await sut.startListening();

      verify(() => service.speak(
          'Multiple matches found: Alpha Hall, Beta Hall. Please select one.'))
          .called(1);
      expect(sut.searchMatches.map((l) => l.id).toList(), ['h1', 'h2']);
    });

    test('selecting a match navigates and clears the list', () async {
      sut.searchMatches.value = [_loc('h1', 'Alpha Hall')];

      sut.selectMatch(_loc('h1', 'Alpha Hall'));

      expect(sut.searchMatches, isEmpty);
      verify(() => service.speak('Navigating to Alpha Hall.')).called(1);
      // See above: Get.toNamed is verified via manual/integration testing.
    });
  });

  group('Requirement 9.2: TTS queue ordering', () {
    /// Returns the completion handler the controller wired into the service.
    Future<void> Function() completionHandler() {
      final captured =
          verify(() => service.onComplete = captureAny()).captured;
      return captured.single as Future<void> Function();
    }

    test('utterances queue while busy and play FIFO on completion',
        () async {
      when(() => service.isSpeaking).thenReturn(true);
      await sut.speak('first');
      await sut.speak('second');
      await sut.speak('third');

      // Nothing interrupted the ongoing utterance.
      verifyNever(() => service.speak(any()));
      expect(sut.ttsQueue.toList(), ['first', 'second', 'third']);

      // Each completion speaks the head of the queue in FIFO order.
      when(() => service.isSpeaking).thenReturn(false);
      final onComplete = completionHandler();
      await onComplete();
      verify(() => service.speak('first')).called(1);
      await onComplete();
      verify(() => service.speak('second')).called(1);
      await onComplete();
      verify(() => service.speak('third')).called(1);
      expect(sut.ttsQueue, isEmpty);

      // Empty queue is a no-op.
      await onComplete();
      verifyNever(() => service.speak('fourth'));
    });

    test('direct speak bypasses the queue when idle', () async {
      when(() => service.isSpeaking).thenReturn(false);

      await sut.speak('hello');

      verify(() => service.speak('hello')).called(1);
      expect(sut.ttsQueue, isEmpty);
    });
  });

  group('Requirement 9.5/9.6: mute behaviour', () {
    test('mute stops TTS, clears the queue and suppresses speech', () async {
      when(() => service.isSpeaking).thenReturn(true);
      await sut.speak('queued');
      expect(sut.ttsQueue, hasLength(1));

      sut.mute();

      expect(sut.isMuted.value, isTrue);
      expect(sut.ttsQueue, isEmpty);
      verify(() => service.stop()).called(1);

      await sut.speak('suppressed');
      verifyNever(() => service.speak('suppressed'));
      expect(sut.ttsQueue, isEmpty);
    });

    test('drain is suppressed while muted', () async {
      when(() => service.isSpeaking).thenReturn(true);
      await sut.speak('queued');

      sut.mute();
      // Re-queue after mute would be suppressed, so seed directly.
      sut.ttsQueue.add('pending');
      sut.isMuted.value = true;

      final onComplete = verify(() => service.onComplete = captureAny())
          .captured
          .single as Future<void> Function();
      when(() => service.isSpeaking).thenReturn(false);
      await onComplete();

      verifyNever(() => service.speak('pending'));
    });

    test('unmute lifts suppression for new utterances', () async {
      sut.mute();
      expect(sut.isMuted.value, isTrue);

      sut.unmute();
      expect(sut.isMuted.value, isFalse);

      when(() => service.isSpeaking).thenReturn(false);
      await sut.speak('audible');
      verify(() => service.speak('audible')).called(1);
    });
  });

  group('Requirement 8.8: microphone permission', () {
    test('denied permission explains and never listens', () async {
      when(() => service.hasMicPermission()).thenAnswer((_) async => false);
      when(() => service.requestMicPermission())
          .thenAnswer((_) async => false);

      await sut.startListening();

      verify(() => service.requestMicPermission()).called(1);
      verifyNever(() => service.startListening(any()));
      verify(() => service.speak(
          'Microphone access is needed for voice search. '
          'Please allow it in the system settings.')).called(1);
    });

    test('granted-on-request permission proceeds to listen', () async {
      when(() => service.hasMicPermission()).thenAnswer((_) async => false);
      when(() => service.requestMicPermission()).thenAnswer((_) async => true);
      _hear(service, '');

      await sut.startListening();

      verify(() => service.startListening(any())).called(1);
    });
  });
}
