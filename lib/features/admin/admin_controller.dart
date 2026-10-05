import 'package:get/get.dart';

import '../../core/models/models.dart';
import '../../data/campus_repository.dart';

class AdminController extends GetxController {
  AdminController({required CampusRepository campusRepository})
      : _campusRepository = campusRepository;

  final CampusRepository _campusRepository;

  final locations = <LocationModel>[].obs;
  final edges = <EdgeModel>[].obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final locs = await _campusRepository.fetchLocations();
      locations.assignAll(locs);
      final eds = await _campusRepository.fetchEdges();
      edges.assignAll(eds);
    } catch (e) {
      errorMessage.value = 'Failed to load data: $e';
    }
  }

  Future<void> createLocation(LocationModel location) async {
    if (!_validateLocation(location)) return;

    try {
      await _campusRepository.insertLocation(location);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to create location: $e';
    }
  }

  Future<void> updateLocation(LocationModel location) async {
    if (!_validateLocation(location)) return;

    try {
      await _campusRepository.updateLocation(location);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to update location: $e';
    }
  }

  /// Deletes a location together with its edges (10.5).
  ///
  /// Atomicity comes from the database, not the client: the `edges` foreign
  /// keys are `ON DELETE CASCADE`, so the single `DELETE FROM locations`
  /// removes edge rows and the location row in one statement. A failed
  /// statement therefore deletes nothing — hence the error message below.
  Future<void> deleteLocation(String id) async {
    try {
      await _campusRepository.deleteLocation(id);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to delete location: $e. Nothing was deleted.';
    }
  }

  Future<void> createEdge(EdgeModel edge) async {
    if (!_validateEdge(edge)) return;

    try {
      await _campusRepository.insertEdge(edge);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to create edge: $e';
    }
  }

  Future<void> deleteEdge(String id) async {
    try {
      await _campusRepository.deleteEdge(id);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to delete edge: $e';
    }
  }

  Future<void> updateEdge(EdgeModel edge) async {
    if (!_validateEdge(edge)) return;

    try {
      await _campusRepository.updateEdge(edge);
      await loadData();
      errorMessage.value = '';
    } catch (e) {
      errorMessage.value = 'Failed to update edge: $e';
    }
  }

  bool _validateLocation(LocationModel location) {
    if (location.name.trim().isEmpty) {
      errorMessage.value = 'Name is required';
      return false;
    }
    if (location.lat.isNaN ||
        location.lng.isNaN ||
        location.lat < -90 ||
        location.lat > 90 ||
        location.lng < -180 ||
        location.lng > 180) {
      errorMessage.value = 'Valid latitude (-90..90) and longitude (-180..180) are required';
      return false;
    }
    return true;
  }

  bool _validateEdge(EdgeModel edge) {
    if (edge.distanceMeters <= 0) {
      errorMessage.value = 'Distance must be greater than 0';
      return false;
    }
    if (edge.fromLocationId == edge.toLocationId) {
      errorMessage.value = 'Self-loops are not allowed';
      return false;
    }
    final fromExists = locations.any((l) => l.id == edge.fromLocationId);
    final toExists = locations.any((l) => l.id == edge.toLocationId);
    if (!fromExists || !toExists) {
      errorMessage.value = 'Both locations must exist';
      return false;
    }
    return true;
  }
}