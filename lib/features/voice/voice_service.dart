import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wraps speech_to_text (STT) and flutter_tts (TTS).
class VoiceService {
  VoiceService() : _tts = FlutterTts(), _stt = SpeechToText(), _isSpeaking = false.obs {
    _tts.setStartHandler(() {
      _isSpeaking.value = true;
    });
    _tts.setCompletionHandler(_onTtsFinished);
    // Cancellation (stop()) and errors must also release the speaking flag,
    // otherwise every later utterance queues forever and TTS goes silent.
    _tts.setCancelHandler(_onTtsFinished);
    _tts.setErrorHandler((message) {
      debugPrint('TTS error: $message');
      _onTtsFinished();
    });
  }

  final FlutterTts _tts;
  final SpeechToText _stt;
  final RxBool _isSpeaking;
  bool get isSpeaking => _isSpeaking.value;

  /// Fired when the current TTS utterance completes. VoiceController sets
  /// this to drain its FIFO queue (Requirement 9.2).
  void Function()? onComplete;

  bool _isListening = false;
  Timer? _listenTimeout;

  /// Whether microphone permission is currently granted (8.8).
  Future<bool> hasMicPermission() => _stt.hasPermission;

  /// Requests microphone permission via the speech_to_text initializer.
  /// Returns true when listening is available afterwards.
  Future<bool> requestMicPermission() => _stt.initialize();

  Future<void> startListening(void Function(String) onResult) async {
    if (_isListening) return;
    _resultDelivered = false;
    _lastWords = '';
    _pendingOnResult = onResult;

    bool available = false;
    try {
      available = await _stt.initialize(
        onError: _onSttError,
        onStatus: (status) => debugPrint('STT status: $status'),
      );
    } catch (e) {
      debugPrint('STT initialize failed: $e');
    }
    if (!available) {
      debugPrint(
        'STT unavailable (mic permission denied, no recognizer, or no '
        'network for cloud recognition).',
      );
      _finishListening('');
      return;
    }

    _isListening = true;
    _listenTimeout?.cancel();
    _listenTimeout = Timer(const Duration(seconds: 10), () {
      // Silence or no final result: fall back to the last partial wording
      // (often complete enough to search) so the mic never dies quietly.
      debugPrint('STT listen timed out; last words: "$_lastWords"');
      _finishListening(_lastWords);
    });

    try {
      await _stt.listen(
        onResult: (result) {
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            debugPrint('STT final: "${result.recognizedWords}"');
            _finishListening(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
          localeId: 'en_US',
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('STT listen failed: $e');
      _finishListening('');
    }
  }

  /// Latest wording heard (final or partial) and the in-flight callback.
  String _lastWords = '';
  void Function(String)? _pendingOnResult;
  bool _resultDelivered = false;

  void _onSttError(SpeechRecognitionError error) {
    debugPrint('STT error: ${error.errorMsg} (permanent: ${error.permanent})');
    // Permanent errors (no match, no network, no recognizer) end the
    // session: deliver whatever we have so the UI responds with a retry
    // prompt instead of hanging on a dead mic.
    if (error.permanent) {
      _finishListening(_lastWords);
    }
  }

  /// Delivers exactly one result per session, then shuts the session down.
  void _finishListening(String text) {
    if (_resultDelivered) return;
    _resultDelivered = true;
    final onResult = _pendingOnResult;
    _pendingOnResult = null;
    _listenTimeout?.cancel();
    _isListening = false;
    unawaited(_stt.stop());
    onResult?.call(text);
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    _isListening = false;
    _listenTimeout?.cancel();
    await _stt.stop();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureTtsConfigured();
    _isSpeaking.value = true;
    try {
      // With awaitSpeakCompletion(true) this future spans the whole
      // utterance; the 45 s cap guards against engines that never report
      // completion, which would otherwise wedge the queue.
      await _tts.speak(text).timeout(const Duration(seconds: 45));
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      try {
        await _tts.stop();
      } catch (_) {}
    } finally {
      _isSpeaking.value = false;
      // Backstop for dropped platform callbacks (notably interrupted
      // utterances): guarantees the controller's queue keeps moving.
      onComplete?.call();
    }
  }

  bool _ttsConfigured = false;

  /// Applies a known-good voice profile once: completion-aware speech,
  /// US English when available, and a clear navigation pace at full volume.
  /// Every step is best-effort so a missing engine can never crash the app.
  Future<void> _ensureTtsConfigured() async {
    if (_ttsConfigured) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      try {
        if (await _tts.isLanguageAvailable('en-US') == true) {
          await _tts.setLanguage('en-US');
        }
      } catch (_) {}
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ttsConfigured = true;
    } catch (e) {
      debugPrint('TTS configuration failed: $e');
    }
  }

  Future<void> stop() async {
    _isSpeaking.value = false;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop failed: $e');
    }
  }

  void _onTtsFinished() {
    _isSpeaking.value = false;
    onComplete?.call();
  }

  void dispose() {
    _listenTimeout?.cancel();
    _stt.stop();
    _tts.stop();
  }
}