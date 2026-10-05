import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/models/location_model.dart';
import '../../data/campus_repository.dart';
import '../navigation/navigation_controller.dart';
import 'voice_service.dart';

class VoiceController extends GetxController {
  VoiceController({
    required VoiceService voiceService,
    required CampusRepository campusRepository,
  })  : _voiceService = voiceService,
        _campusRepository = campusRepository {
    // Drain the FIFO TTS queue whenever the service finishes an utterance
    // (Requirement 9.2).
    _voiceService.onComplete = _drainTtsQueue;
  }

  final VoiceService _voiceService;
  final CampusRepository _campusRepository;

  final isMuted = false.obs;
  final isListening = false.obs;
  final ttsQueue = <String>[].obs;

  /// Voice-search matches awaiting user selection (8.7). Non-empty drives
  /// the on-screen match list; tapping one navigates to it.
  final searchMatches = <LocationModel>[].obs;

  Future<void> startListening() async {
    if (isListening.value) return;
    // 8.8: microphone permission first, with an explanatory dialog.
    if (!await _voiceService.hasMicPermission()) {
      final proceed = await _confirmMicPermission();
      if (proceed != true) return;
      final granted = await _voiceService.requestMicPermission();
      if (!granted) {
        _speak(
          'Microphone access is needed for voice search. '
          'Please allow it in the system settings.',
        );
        return;
      }
    }
    isListening.value = true;
    try {
      // The service delivers exactly one result (final, partial fallback,
      // timeout, or error) through _onSttResult, which clears the flag.
      await _voiceService.startListening(_onSttResult);
    } catch (_) {
      isListening.value = false;
      _speak('Voice search is unavailable right now. Please try again.');
    }
  }

  /// Explains why microphone access is needed (8.8). Returns true when the
  /// user taps Allow. Skipped where no UI overlay exists (unit tests).
  Future<bool?> _confirmMicPermission() async {
    if (Get.overlayContext == null) return true;
    return Get.dialog<bool>(
      AlertDialog(
        title: const Text('Microphone access'),
        content: const Text(
          'Voice search needs microphone access so the app can hear the '
          'destination name you speak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  void _onSttResult(String text) async {
    isListening.value = false;
    if (text.trim().isEmpty) {
      _speak('No location found. Please try again.');
      return;
    }

    List<LocationModel> matches;
    try {
      matches = await _campusRepository.searchLocations(text);
    } catch (_) {
      _speak('Search is unavailable while offline. Please try again.');
      return;
    }
    if (matches.isEmpty) {
      // 8.5: spoken no-match response + retry prompt.
      searchMatches.clear();
      _speak('No location found. Please try again.');
    } else if (matches.length == 1) {
      // 8.6: exactly one match → begin route computation to it.
      searchMatches.clear();
      _speak('Navigating to ${matches.first.name}.');
      _openNavigation(matches.first.id);
    } else {
      // 8.7: speak the names AND show them on screen for selection.
      searchMatches.value = matches;
      final names = matches.map((l) => l.name).join(', ');
      _speak('Multiple matches found: $names. Please select one.');
    }
  }

  /// User picked one of the on-screen voice matches (8.7).
  void selectMatch(LocationModel location) {
    searchMatches.clear();
    _speak('Navigating to ${location.name}.');
    _openNavigation(location.id);
  }

  void clearMatches() => searchMatches.clear();

  void _openNavigation(String locationId) {
    // Already on the navigation screen: its controller instance is the one
    // the view observes, so start directly on it. Otherwise push the route
    // with the destination id; NavigationController.onReady takes it over.
    if (Get.currentRoute == '/navigation' &&
        Get.isRegistered<NavigationController>()) {
      Get.find<NavigationController>().startNavigationTo(locationId);
      return;
    }
    Get.toNamed('/navigation', arguments: locationId);
  }

  Future<void> stopListening() async {
    await _voiceService.stopListening();
    isListening.value = false;
  }

  Future<void> speak(String text) async {
    if (isMuted.value) return;
    if (_voiceService.isSpeaking) {
      ttsQueue.add(text);
    } else {
      await _voiceService.speak(text);
    }
  }

  /// Plays queued utterances FIFO after the current one completes (9.2).
  /// Invoked by [VoiceService.onComplete], which the service fires from the
  /// completion handler, the cancel handler, the error handler, AND the
  /// speak backstop — so re-entrant triggers are the norm, not the edge
  /// case. [_draining] serialises them; the loop (not single-step) ensures
  /// nothing is stranded; the tail check closes the unlock-gap window.
  bool _draining = false;

  Future<void> _drainTtsQueue() async {
    if (_draining) return;
    if (isMuted.value || ttsQueue.isEmpty) return;
    _draining = true;
    try {
      while (!isMuted.value && ttsQueue.isNotEmpty) {
        final next = ttsQueue.removeAt(0);
        await _voiceService.speak(next);
      }
    } finally {
      _draining = false;
      if (!isMuted.value &&
          ttsQueue.isNotEmpty &&
          !_voiceService.isSpeaking) {
        unawaited(_drainTtsQueue());
      }
    }
  }

  void mute() {
    isMuted.value = true;
    ttsQueue.clear();
    _voiceService.stop();
  }

  void unmute() {
    isMuted.value = false;
  }

  void _speak(String text) {
    if (!isMuted.value) {
      speak(text);
    }
  }

  @override
  void onClose() {
    // Detach first so a late platform callback cannot trigger a drain
    // against a disposed service.
    _voiceService.onComplete = null;
    _voiceService.dispose();
    super.onClose();
  }
}
