import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../navigation_controller.dart';
import '../../voice/voice_controller.dart';

class NavigationView extends GetView<NavigationController> {
  const NavigationView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Obx(() {
            final route = controller.activeRoute.value;
            final polylinePoints = route != null
                ? route.nodes
                    .map((n) => LatLng(n.lat, n.lng))
                    .toList()
                : <LatLng>[];

            return GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: LatLng(7.5, 5.5),
                zoom: 16,
              ),
              onMapCreated: controller.onNavigationMapCreated,
              onCameraMove: controller.onNavigationCameraMove,
              polylines: {
                if (polylinePoints.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: polylinePoints,
                    color: Colors.blue,
                    width: 5,
                  ),
              },
              markers: {
                if (route != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: LatLng(
                      route.destination.lat,
                      route.destination.lng,
                    ),
                    infoWindow: InfoWindow(title: route.destination.name),
                  ),
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            );
          }),
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Obx(() {
              if (!controller.isNavigating.value) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 9.5/9.6: mute toggle for spoken instructions.
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Navigation',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey),
                            ),
                          ),
                          Obx(() {
                            final voice = Get.find<VoiceController>();
                            final muted = voice.isMuted.value;
                            return IconButton(
                              icon: Icon(muted
                                  ? Icons.volume_off
                                  : Icons.volume_up),
                              tooltip: muted
                                  ? 'Unmute voice directions'
                                  : 'Mute voice directions',
                              onPressed: () {
                                if (muted) {
                                  voice.unmute();
                                } else {
                                  voice.mute();
                                }
                              },
                            );
                          }),
                        ],
                      ),
                      Obx(() {
                        if (controller.isRerouting.value) {
                          return const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Rerouting...'),
                            ],
                          );
                        }
                        if (controller.activeRoute.value != null &&
                            controller.currentStepIndex.value <
                                (controller.activeRoute.value?.turnInstructions
                                        .length ??
                                    0)) {
                          return Text(
                            controller.activeRoute.value!
                                .turnInstructions[controller.currentStepIndex.value],
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          );
                        }
                        if (controller.isNavigating.value &&
                            controller.routeErrorMessage.value.isEmpty) {
                          return const Row(
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Computing route...'),
                            ],
                          );
                        }
                        return const Text('Navigation complete');
                      }),
                      const SizedBox(height: 8),
                      Obx(() => Text(
                        'Remaining: ${controller.remainingDistance.value.toStringAsFixed(0)} m',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      )),
                    ],
                  ),
                ),
              );
            }),
          ),
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Obx(() {
              // Requirement 13.3: location permission denial explains itself
              // and links to the device settings.
              if (controller.needsLocationPermission.value) {
                return Card(
                  color: Colors.orange.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Live navigation is unavailable without location access.',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.openLocationSettings,
                          child: const Text(
                            'Open Settings',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // Requirement 5.4: visible "no navigable path" message.
              if (controller.routeErrorMessage.value.isNotEmpty) {
                return Card(
                  color: Colors.red.shade800,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      controller.routeErrorMessage.value,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }
              return controller.hasGPSSignal.value
                  ? const SizedBox.shrink()
                  : const Card(
                      color: Colors.orange,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'GPS signal lost. Navigation paused.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
            }),
          ),
          Positioned(
            bottom: 30,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: controller.cancelNavigation,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Cancel Navigation', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}