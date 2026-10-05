import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/models.dart';
import 'campus_repository.dart';
import 'supabase_service.dart';

class SupabaseCampusRepository extends CampusRepository {
  final SupabaseService _supabaseService;
  final SharedPreferences _prefs;
  bool _isOfflineMode = false;

  @override
  bool get isOfflineMode => _isOfflineMode;

  SupabaseCampusRepository({
    required SupabaseService supabaseService,
    required SharedPreferences prefs,
  })  : _supabaseService = supabaseService,
        _prefs = prefs;

  @override
  Future<List<LocationModel>> fetchLocations() async {
    try {
      final locations = await _supabaseService.getLocations();
      _isOfflineMode = false;
      await _cacheLocations(locations);
      return locations;
    } on PostgrestException {
      _isOfflineMode = true;
      final cached = await _readCachedLocations();
      if (cached.isNotEmpty) return cached;
      rethrow;
    } on Exception {
      _isOfflineMode = true;
      final cached = await _readCachedLocations();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<List<EdgeModel>> fetchEdges() async {
    try {
      final edges = await _supabaseService.getEdges();
      _isOfflineMode = false;
      await _cacheEdges(edges);
      return edges;
    } on PostgrestException {
      _isOfflineMode = true;
      final cached = await _readCachedEdges();
      if (cached.isNotEmpty) return cached;
      rethrow;
    } on Exception {
      _isOfflineMode = true;
      final cached = await _readCachedEdges();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  @override
  Future<void> insertLocation(LocationModel loc) async {
    await _supabaseService.insertLocation(loc);
    await _cacheLocations(await _supabaseService.getLocations());
  }

  @override
  Future<void> updateLocation(LocationModel loc) async {
    await _supabaseService.updateLocation(loc);
    await _cacheLocations(await _supabaseService.getLocations());
  }

  @override
  Future<void> deleteLocation(String id) async {
    await _supabaseService.deleteLocation(id);
    await _cacheLocations(await _supabaseService.getLocations());
  }

  @override
  Future<void> insertEdge(EdgeModel edge) async {
    await _supabaseService.insertEdge(edge);
    await _cacheEdges(await _supabaseService.getEdges());
  }

  @override
  Future<void> updateEdge(EdgeModel edge) async {
    await _supabaseService.updateEdge(edge);
    await _cacheEdges(await _supabaseService.getEdges());
  }

  @override
  Future<void> deleteEdge(String id) async {
    await _supabaseService.deleteEdge(id);
    await _cacheEdges(await _supabaseService.getEdges());
  }

  @override
  Future<List<LocationModel>> searchLocations(String query) async {
    final allLocations = await _supabaseService.getLocations();
    final lowerQuery = query.toLowerCase();
    return allLocations
        .where((loc) => loc.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  @override
  Stream<List<LocationModel>> locationsStream() {
    return _supabaseService.locationsStream();
  }

  @override
  Stream<List<EdgeModel>> edgesStream() {
    return _supabaseService.edgesStream();
  }

  static const String _locationsKey = 'campus_locations';
  static const String _edgesKey = 'campus_edges';

  Future<void> _cacheLocations(List<LocationModel> locations) async {
    final jsonList = locations.map((l) => l.toJson()).toList();
    await _prefs.setString(_locationsKey, jsonEncode(jsonList));
  }

  Future<List<LocationModel>> _readCachedLocations() async {
    final cached = _prefs.getString(_locationsKey);
    if (cached == null) return [];
    try {
      final list = jsonDecode(cached) as List;
      return list.map((item) {
        // Backward compat: old cache stored each item as an encoded String.
        final map = item is String
            ? jsonDecode(item) as Map<String, dynamic>
            : item as Map<String, dynamic>;
        return LocationModel.fromJson(map);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _cacheEdges(List<EdgeModel> edges) async {
    final jsonList = edges.map((e) => e.toJson()).toList();
    await _prefs.setString(_edgesKey, jsonEncode(jsonList));
  }

  Future<List<EdgeModel>> _readCachedEdges() async {
    final cached = _prefs.getString(_edgesKey);
    if (cached == null) return [];
    try {
      final list = jsonDecode(cached) as List;
      return list.map((item) {
        final map = item is String
            ? jsonDecode(item) as Map<String, dynamic>
            : item as Map<String, dynamic>;
        return EdgeModel.fromJson(map);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
