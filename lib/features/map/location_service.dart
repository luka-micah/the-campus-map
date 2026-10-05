import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationService {
  final RxBool hasPermission = false.obs;
  final RxBool isLocationAvailable = false.obs;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<bool>? _signalSubscription;

  LocationService();

  Stream<Position> get positionStream => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

  Stream<bool> get hasSignal => positionStream
      .map((_) => true)
      .timeout(const Duration(seconds: 15), onTimeout: (sink) {
        sink.add(false);
        sink.close();
      });

  Future<void> requestPermission() async {
    try {
      final status = await Geolocator.requestPermission();
      hasPermission.value = status == LocationPermission.whileInUse ||
          status == LocationPermission.always;
    } catch (_) {
      hasPermission.value = false;
    }
  }

  /// Opens the OS app-settings screen so the user can grant location access
  /// after a denial (Requirements 13.3, 13.4).
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<LatLng> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      // Return default BOUESTI coordinates if GPS fails
      return const LatLng(7.5, 5.5);
    }
  }

  void dispose() {
    _positionSubscription?.cancel();
    _signalSubscription?.cancel();
  }
}