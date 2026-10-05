import '../core/models/models.dart';

/// Abstract data façade — all controllers interact with Supabase through
/// implementations of this class only.
///
/// The concrete implementation ([SupabaseCampusRepository]) caches results to
/// `shared_preferences` on every successful fetch and falls back to the cache
/// on network failure.
abstract class CampusRepository {
  /// Whether the most recent fetch was served from the offline cache.
  ///
  /// Controllers mirror this flag to banners (Requirement 14.1): cached data
  /// displays with an "outdated" notice instead of failing silently.
  bool get isOfflineMode;

  // ──────────────────────────────────────────────────────────────────────────
  // Location operations
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns all campus location records.
  ///
  /// On network failure, implementations SHOULD return the last cached result
  /// and signal offline mode to calling controllers.
  Future<List<LocationModel>> fetchLocations();

  /// Inserts a new [LocationModel] row into the `locations` table.
  Future<void> insertLocation(LocationModel loc);

  /// Updates an existing [LocationModel] row identified by [loc.id].
  Future<void> updateLocation(LocationModel loc);

  /// Deletes the location with [id] and its associated edges atomically.
  Future<void> deleteLocation(String id);

  /// Returns locations matching [query] (case-insensitive partial match
  /// against name and department; voice-command wrappers like
  /// "take me to ..." are ignored). Blank queries return [].
  Future<List<LocationModel>> searchLocations(String query);

  /// A stream that emits a fresh list of [LocationModel] records whenever
  /// the `locations` table changes via Supabase Realtime.
  Stream<List<LocationModel>> locationsStream();

  // ──────────────────────────────────────────────────────────────────────────
  // Edge operations
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns all campus edge records.
  Future<List<EdgeModel>> fetchEdges();

  /// Inserts a new [EdgeModel] row into the `edges` table.
  Future<void> insertEdge(EdgeModel edge);

  /// Updates an existing [EdgeModel] row identified by [edge.id].
  Future<void> updateEdge(EdgeModel edge);

  /// Deletes the edge with [id] from the `edges` table.
  Future<void> deleteEdge(String id);

  /// A stream that emits a fresh list of [EdgeModel] records whenever
  /// the `edges` table changes via Supabase Realtime.
  Stream<List<EdgeModel>> edgesStream();
}
