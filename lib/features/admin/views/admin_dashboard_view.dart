import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/models/models.dart';
import '../../auth/auth_controller.dart';
import '../admin_controller.dart';

class AdminDashboardView extends GetView<AdminController> {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => Get.find<AuthController>().logout(),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(controller.errorMessage.value, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: controller.loadData, child: const Text('Retry')),
              ],
            ),
          );
        }
        return ListView(
          children: [
            _buildSection(
              'Locations',
              controller.locations,
              (loc) => loc.name,
              () => _showLocationForm(context),
              (loc) => _showLocationForm(context, location: loc),
              (loc) => controller.deleteLocation(loc.id),
            ),
            _buildSection(
              'Edges',
              controller.edges,
              (e) => '${e.fromLocationId} \u2192 ${e.toLocationId} (${e.distanceMeters}m)',
              () => _showEdgeForm(context),
              (e) => _showEdgeForm(context, edge: e),
              (e) => controller.deleteEdge(e.id),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSection<T>(
    String title,
    RxList<T> items,
    String Function(T) getTitle,
    VoidCallback onCreate,
    void Function(T) onEdit,
    Future<void> Function(T) onDelete,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(icon: const Icon(Icons.add), onPressed: onCreate),
          ),
          ...items.map((item) => ListTile(
            title: Text(getTitle(item)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(item)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    final confirm = await Get.dialog<bool>(
                      AlertDialog(
                        title: const Text('Delete?'),
                        content: Text('Delete ${getTitle(item)}?'),
                        actions: [
                          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Get.back(result: true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (confirm == true) await onDelete(item);
                  },
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  void _showLocationForm(BuildContext context, {LocationModel? location}) {
    final isEdit = location != null;
    final nameCtrl = TextEditingController(text: location?.name ?? '');
    final deptCtrl = TextEditingController(text: location?.department ?? '');
    final latCtrl = TextEditingController(text: location?.lat.toString() ?? '');
    final lngCtrl = TextEditingController(text: location?.lng.toString() ?? '');
    final hoursCtrl = TextEditingController(text: location?.hours ?? '');

    Get.dialog(
      AlertDialog(
        title: Text(isEdit ? 'Edit Location' : 'Create Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              TextField(controller: deptCtrl, decoration: const InputDecoration(labelText: 'Department')),
              TextField(controller: latCtrl, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: TextInputType.number),
              TextField(controller: lngCtrl, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: TextInputType.number),
              TextField(controller: hoursCtrl, decoration: const InputDecoration(labelText: 'Hours')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            // 10.7: missing/unparseable required fields are rejected here
            // with a message and the form stays open (no submission).
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                Get.snackbar('Validation', 'Name is required');
                return;
              }
              final lat = double.tryParse(latCtrl.text.trim());
              final lng = double.tryParse(lngCtrl.text.trim());
              if (lat == null || lng == null) {
                Get.snackbar('Validation', 'Latitude and longitude must be numbers');
                return;
              }
              final loc = LocationModel(
                // Empty id: Supabase applies the gen_random_uuid() default.
                id: location?.id ?? '',
                name: nameCtrl.text.trim(),
                department: deptCtrl.text.trim(),
                lat: lat,
                lng: lng,
                hours: hoursCtrl.text.trim(),
                createdAt: location?.createdAt ?? DateTime.now(),
              );
              if (isEdit) {
                await controller.updateLocation(loc);
              } else {
                await controller.createLocation(loc);
              }
              if (controller.errorMessage.value.isEmpty) {
                Get.back();
              } else {
                Get.snackbar('Validation', controller.errorMessage.value);
              }
            },
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  void _showEdgeForm(BuildContext context, {EdgeModel? edge}) {
    final isEdit = edge != null;
    final fromCtrl = TextEditingController(text: edge?.fromLocationId ?? '');
    final toCtrl = TextEditingController(text: edge?.toLocationId ?? '');
    final distCtrl = TextEditingController(text: edge?.distanceMeters.toString() ?? '');

    Get.dialog(
      AlertDialog(
        title: Text(isEdit ? 'Edit Edge' : 'Create Edge'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: fromCtrl.text.isEmpty ? null : fromCtrl.text,
                items: controller.locations
                    .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => fromCtrl.text = v ?? '',
                decoration: const InputDecoration(labelText: 'From Location'),
              ),
              DropdownButtonFormField<String>(
                initialValue: toCtrl.text.isEmpty ? null : toCtrl.text,
                items: controller.locations
                    .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => toCtrl.text = v ?? '',
                decoration: const InputDecoration(labelText: 'To Location'),
              ),
              TextField(controller: distCtrl, decoration: const InputDecoration(labelText: 'Distance (meters)'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (fromCtrl.text.isEmpty || toCtrl.text.isEmpty) {
                Get.snackbar('Validation', 'Both locations must be selected');
                return;
              }
              final distance = double.tryParse(distCtrl.text.trim());
              if (distance == null) {
                Get.snackbar('Validation', 'Distance must be a number');
                return;
              }
              final e = EdgeModel(
                // Empty id: Supabase applies the gen_random_uuid() default.
                id: edge?.id ?? '',
                fromLocationId: fromCtrl.text,
                toLocationId: toCtrl.text,
                distanceMeters: distance,
              );
              if (isEdit) {
                await controller.updateEdge(e);
              } else {
                await controller.createEdge(e);
              }
              if (controller.errorMessage.value.isEmpty) {
                Get.back();
              } else {
                Get.snackbar('Validation', controller.errorMessage.value);
              }
            },
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }
}