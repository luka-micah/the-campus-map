import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:get/get.dart';

import '../map_controller.dart';
import '../location_service.dart';
import '../../auth/auth_controller.dart';
import '../../voice/voice_controller.dart';
import '../../../../core/models/location_model.dart';

class MapView extends StatelessWidget {
  final LatLng _boustiCoordinate = const LatLng(7.5, 5.5);
  final TextEditingController _searchCtrl = TextEditingController();

  MapView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapController>();
    final voiceController = Get.find<VoiceController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Map'),
        actions: [
          // Basemap style: standard → satellite → hybrid.
          Obx(() {
            final current = controller.mapType.value;
            return IconButton(
              icon: Icon(
                current == MapType.normal ? Icons.satellite_alt : Icons.map,
              ),
              tooltip: 'Switch to ${controller.nextMapTypeLabel} view',
              onPressed: controller.cycleMapType,
            );
          }),
          // 2D/3D perspective toggle.
          Obx(() {
            final is3D = controller.is3DMode.value;
            return IconButton(
              icon: Icon(is3D ? Icons.map : Icons.view_in_ar),
              tooltip: is3D ? 'Switch to 2D view' : 'Switch to 3D view',
              onPressed: controller.toggle3DMode,
            );
          }),
          // Visible only to admins (profiles.is_admin).
          Obx(() {
            final authController = Get.find<AuthController>();
            if (authController.isAdmin.value != true) {
              return const SizedBox.shrink();
            }
            return IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin dashboard',
              onPressed: () => Get.toNamed('/admin'),
            );
          }),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => Get.find<AuthController>().logout(),
          ),
        ],
      ),
      body: Obx(
        () => Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _boustiCoordinate,
                zoom: 14,
              ),
              mapType: controller.mapType.value,
              onMapCreated: controller.onMapCreated,
              onCameraMove: controller.onCameraMove,
              markers: _buildMarkers(controller),
              myLocationEnabled: controller.userPosition.value != null,
              myLocationButtonEnabled: true,
            ),
            // Destination search field + live results.
            _buildSearchBar(controller, voiceController),
            // Status banners live in their own slot BELOW the search bar so
            // the search field/results can never cover them (or vice versa).
            // While a results dropdown is open the slot drops beneath it.
            if (controller.hasFetchError.value ||
                controller.isOfflineMode.value)
              Positioned(
                top: controller.searchQuery.value.trim().isEmpty ? 76 : 324,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.hasFetchError.value)
                      _buildErrorBanner(controller),
                    if (controller.isOfflineMode.value)
                      _buildOfflineBanner(),
                  ],
                ),
              ),
            if (controller.userPosition.value == null &&
                Get.find<LocationService>().hasPermission.value == false)
              _buildBrowseOnlyBanner(controller),
            // 8.7: on-screen voice-search matches for the user to select.
            if (voiceController.searchMatches.isNotEmpty)
              _buildMatchCard(voiceController),
          ],
        ),
      ),
      // 8.1: voice destination search control.
      floatingActionButton: Obx(
        () => FloatingActionButton(
          onPressed: () {
            if (voiceController.isListening.value) {
              voiceController.stopListening();
            } else {
              voiceController.startListening();
            }
          },
          tooltip: voiceController.isListening.value
              ? 'Stop listening'
              : 'Voice search',
          child: Icon(
            voiceController.isListening.value ? Icons.stop : Icons.mic,
          ),
        ),
      ),
    );
  }

  /// On-screen list of voice-search matches (8.7). Tapping a match begins
  /// navigation to it; the close button dismisses the list.
  Widget _buildMatchCard(VoiceController voiceController) {
    final matches = voiceController.searchMatches;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(blurRadius: 8, color: Colors.black26),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select destination',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: voiceController.clearMatches,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final match = matches[index];
                  return ListTile(
                    leading: const Icon(Icons.place),
                    title: Text(match.name),
                    subtitle: Text(match.department),
                    onTap: () => voiceController.selectMatch(match),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Destination search: text field with live matches; tapping a match
  /// opens its details dialog (with Navigate), like tapping a marker.
  Widget _buildSearchBar(
    MapController controller,
    VoiceController voiceController,
  ) {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Obx(
              () => TextField(
                controller: _searchCtrl,
                onChanged: controller.search,
                decoration: InputDecoration(
                  hintText: 'Search campus locations...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.searchQuery.value.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            controller.clearSearch();
                          },
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Obx(() {
            // Voice multi-match card takes precedence when both are visible.
            if (voiceController.searchMatches.isNotEmpty) {
              return const SizedBox.shrink();
            }
            final query = controller.searchQuery.value.trim();
            if (query.isEmpty) return const SizedBox.shrink();
            final results = controller.searchResults;
            return Container(
              margin: const EdgeInsets.only(top: 8),
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(blurRadius: 8, color: Colors.black26),
                ],
              ),
              child: results.isEmpty
                  ? const ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('No matching locations'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final match = results[index];
                        return ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(match.name),
                          subtitle: Text(match.department),
                          onTap: () {
                            _searchCtrl.clear();
                            controller.clearSearch();
                            controller.onMarkerTapped(match.id);
                          },
                        );
                      },
                    ),
            );
          }),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers(MapController controller) {
    return controller.locations
        .map<Marker>((LocationModel loc) => Marker(
              markerId: MarkerId(loc.id),
              position: LatLng(loc.lat, loc.lng),
              infoWindow: InfoWindow(
                title: loc.name,
                snippet: '${loc.department} | ${loc.hours}',
              ),
              onTap: () => controller.onMarkerTapped(loc.id),
            ))
        .toSet();
  }

  Widget _buildErrorBanner(MapController controller) {
    // Slot-friendly: the parent Positioned handles placement, so this is a
    // plain full-width row (previously an Align that collided with the
    // search bar and buried its own Retry button).
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Failed to load map data',
              style: TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => controller.fetchLocations(),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Data may be outdated — offline mode',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseOnlyBanner(MapController controller) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.shade800,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'GPS denied — browse-only mode enabled',
                style: TextStyle(color: Colors.white),
              ),
            ),
            TextButton(
              onPressed: () => controller.refreshLocation(),
              child: const Text('Enable',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
