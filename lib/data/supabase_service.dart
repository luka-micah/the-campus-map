import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/models/models.dart';

const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://lmuqepfltdjssmlssnbn.supabase.co',
);
const String _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_9fN55L5rXQK1XI1_S8VcNw_AkiS_AvJ',
);

class SupabaseService {
  SupabaseService._();

  static final SupabaseService _instance = SupabaseService._();

  static SupabaseService get instance => _instance;

  late final SupabaseClient _client;

  SupabaseClient get client => _client;

  Future<void> initialise() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      publishableKey: _supabasePublishableKey,
    );
    _client = Supabase.instance.client;
  }

  Future<List<LocationModel>> getLocations() async {
    final response = await _client.from('locations').select();
    return response.map((json) => LocationModel.fromJson(json)).toList();
  }

  Future<List<EdgeModel>> getEdges() async {
    final response = await _client.from('edges').select();
    return response.map((json) => EdgeModel.fromJson(json)).toList();
  }

  Future<List<UserProfile>> getProfiles() async {
    final response = await _client.from('profiles').select();
    return response.map((json) => UserProfile.fromJson(json)).toList();
  }

  Future<void> insertLocation(LocationModel loc) async {
    final json = loc.toJson();
    // New rows use id '' from the admin form: omit it so Postgres applies
    // the gen_random_uuid() default (millis strings are not valid UUIDs).
    if ((json['id'] as String).isEmpty) json.remove('id');
    await _client.from('locations').insert(json).select();
  }

  Future<void> updateLocation(LocationModel loc) async {
    // id and created_at are immutable: never overwrite them on update.
    final json = loc.toJson()
      ..remove('id')
      ..remove('created_at');
    await _client.from('locations').update(json).eq('id', loc.id).select();
  }

  Future<void> insertEdge(EdgeModel edge) async {
    final json = edge.toJson();
    if ((json['id'] as String).isEmpty) json.remove('id');
    await _client.from('edges').insert(json).select();
  }

  Future<void> updateEdge(EdgeModel edge) async {
    final json = edge.toJson()..remove('id');
    await _client.from('edges').update(json).eq('id', edge.id).select();
  }

  Future<void> deleteLocation(String id) async {
    await _client.from('locations').delete().eq('id', id).select();
  }

  Future<void> deleteEdge(String id) async {
    await _client.from('edges').delete().eq('id', id).select();
  }

  Stream<List<LocationModel>> locationsStream() {
    return _client
        .from('locations')
        .stream(primaryKey: ['id'])
        .map(
          (event) => event.map((json) => LocationModel.fromJson(json)).toList(),
        );
  }

  Stream<List<EdgeModel>> edgesStream() {
    return _client
        .from('edges')
        .stream(primaryKey: ['id'])
        .map((event) => event.map((json) => EdgeModel.fromJson(json)).toList());
  }
}
