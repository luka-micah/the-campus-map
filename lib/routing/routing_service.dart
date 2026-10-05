import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/models/edge_model.dart';
import '../core/models/graph_node.dart';
import '../core/models/location_model.dart';
import '../core/models/route_model.dart';
import '../core/models/weighted_edge.dart';
import '../data/campus_repository.dart';

// ---------------------------------------------------------------------------
// RoutingService
// ---------------------------------------------------------------------------

/// Builds and queries the campus walking-path graph.
///
/// Typical lifecycle:
/// 1. Call [buildGraph] once after fetching locations and edges from the
///    repository (and again whenever the repository emits an update).
/// 2. Call [nearestNode] to resolve a GPS [LatLng] to a [GraphNode].
/// 3. Call [computeRoute] with origin and destination [GraphNode]s.
class RoutingService {
  // ---- internal state -------------------------------------------------------

  /// All nodes keyed by their [GraphNode.id].
  final Map<String, GraphNode> _graphNodes = {};

  /// Adjacency list: node id → list of outgoing weighted edges.
  final AdjacencyList _adjacencyList = {};

  /// When `true`, a rebuild is pending (e.g. repository data has changed).
  ///
  /// Set to `true` as soon as a [CampusRepository] stream event arrives and
  /// cleared at the end of [buildGraph]. While pending, [computeRouteAsync]
  /// queues incoming requests instead of running them against the stale
  /// graph; the queue is drained right after the rebuild (Requirement 4.5).
  /// The synchronous [computeRoute] does not queue — prefer
  /// [computeRouteAsync] for calls that may race a rebuild.
  bool rebuildPending = false;

  /// Route requests that arrived while [rebuildPending] was true.
  final List<void Function()> _requestQueue = [];

  /// Latest known data, used to rebuild when either stream fires.
  List<LocationModel> _latestLocations = [];
  List<EdgeModel> _latestEdges = [];

  StreamSubscription<List<EdgeModel>>? _edgesSubscription;
  StreamSubscription<List<LocationModel>>? _locationsSubscription;

  // ---- public API -----------------------------------------------------------

  /// Constructs the in-memory adjacency-list graph from [locations] and
  /// [edges] fetched from the repository.
  ///
  /// Edges that reference location IDs not present in [locations] are silently
  /// skipped (logged via [debugPrint]) so that a single malformed edge never
  /// prevents the rest of the graph from being usable.
  ///
  /// Setting [rebuildPending] before clearing ensures any concurrent
  /// [computeRouteAsync] call can detect the upcoming mutation.
  void buildGraph(List<LocationModel> locations, List<EdgeModel> edges) {
    rebuildPending = true;

    _latestLocations = List.of(locations);
    _latestEdges = List.of(edges);

    _graphNodes.clear();
    _adjacencyList.clear();

    // 1. Build node map from locations.
    for (final loc in locations) {
      final node = GraphNode(
        id: loc.id,
        name: loc.name,
        lat: loc.lat,
        lng: loc.lng,
      );
      _graphNodes[loc.id] = node;
      _adjacencyList[loc.id] = [];
    }

    // 2. Add edges; skip any that reference unknown node IDs.
    for (final edge in edges) {
      final fromExists = _graphNodes.containsKey(edge.fromLocationId);
      final toExists = _graphNodes.containsKey(edge.toLocationId);

      if (!fromExists || !toExists) {
        // Log the malformed edge and continue — do not crash.
        debugPrint(
          '[RoutingService] Skipping malformed edge ${edge.id}: '
          'fromLocationId=${edge.fromLocationId} (exists=$fromExists), '
          'toLocationId=${edge.toLocationId} (exists=$toExists)',
        );
        continue;
      }

      // Forward direction.
      _adjacencyList[edge.fromLocationId]!.add(
        WeightedEdge(
          targetNodeId: edge.toLocationId,
          weight: edge.distanceMeters,
        ),
      );

      // Reverse direction (undirected graph — each edge is bidirectional).
      _adjacencyList[edge.toLocationId]!.add(
        WeightedEdge(
          targetNodeId: edge.fromLocationId,
          weight: edge.distanceMeters,
        ),
      );
    }

    rebuildPending = false;
    _drainQueue();
  }

  /// Runs [computeRoute] unless a rebuild is pending, in which case the
  /// request is queued and completed after the fresh graph is built
  /// (Requirement 4.5).
  Future<RouteModel?> computeRouteAsync(
    GraphNode origin,
    GraphNode destination,
  ) {
    if (!rebuildPending) return Future.value(computeRoute(origin, destination));
    final completer = Completer<RouteModel?>();
    _requestQueue.add(() {
      if (!completer.isCompleted) {
        completer.complete(computeRoute(origin, destination));
      }
    });
    return completer.future;
  }

  /// Completes every request queued while a rebuild was pending.
  void _drainQueue() {
    if (_requestQueue.isEmpty) return;
    final queued = List.of(_requestQueue);
    _requestQueue.clear();
    for (final request in queued) {
      request();
    }
  }

  // --------------------------------------------------------------------------
  // nearestNode
  // --------------------------------------------------------------------------

  /// Returns the [GraphNode] whose geographic position is closest to
  /// [position], measured by the Haversine great-circle distance.
  ///
  /// This is an O(n) scan over all nodes; acceptable for campus-scale graphs
  /// (expected < 200 nodes).
  ///
  /// Throws a [StateError] if the graph contains no nodes (i.e. [buildGraph]
  /// has not been called or was called with an empty location list).
  GraphNode nearestNode(LatLng position) {
    if (_graphNodes.isEmpty) {
      throw StateError(
        'nearestNode called on an empty graph. '
        'Call buildGraph with at least one location first.',
      );
    }

    GraphNode? nearest;
    double minDistance = double.infinity;

    for (final node in _graphNodes.values) {
      final d = _haversineMeters(
        position.latitude,
        position.longitude,
        node.lat,
        node.lng,
      );
      if (d < minDistance) {
        minDistance = d;
        nearest = node;
      }
    }

    // nearest is guaranteed non-null here because _graphNodes is non-empty.
    return nearest!;
  }

  // --------------------------------------------------------------------------
  // computeRoute
  // --------------------------------------------------------------------------

  /// Runs Dijkstra's algorithm from [origin] to [destination] using a
  /// [HeapPriorityQueue] (min-heap) from the `collection` package.
  ///
  /// Returns a [RouteModel] on success, or `null` when no path exists.
  ///
  /// Algorithm notes:
  /// - Early exit: as soon as the destination node is dequeued, the shortest
  ///   distance is finalised and path reconstruction begins immediately.
  /// - Stale entries: because Dart's [HeapPriorityQueue] does not support
  ///   decrease-key, entries with a recorded distance greater than the
  ///   best-known distance are silently skipped (`d > dist[u]`).
  /// - The adjacency list is undirected (both directions are added in
  ///   [buildGraph]), so symmetry (Requirement 5.8) holds automatically.
  RouteModel? computeRoute(GraphNode origin, GraphNode destination) {
    // Guard: both nodes must be present in the graph.
    if (!_graphNodes.containsKey(origin.id) ||
        !_graphNodes.containsKey(destination.id)) {
      return null;
    }

    // ---- initialise --------------------------------------------------------
    // dist maps nodeId → best-known distance from origin (infinity = unknown).
    final Map<String, double> dist = {
      for (final id in _graphNodes.keys) id: double.infinity,
    };
    dist[origin.id] = 0.0;

    // prev maps nodeId → predecessor nodeId for path reconstruction.
    final Map<String, String?> prev = {
      for (final id in _graphNodes.keys) id: null,
    };

    // Min-heap ordered by (distance, nodeId).  The comparator sorts by
    // distance first; nodeId is used only as a tiebreaker for determinism.
    final pq = HeapPriorityQueue<_DijkstraEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        return cmp != 0 ? cmp : a.nodeId.compareTo(b.nodeId);
      },
    );
    pq.add(_DijkstraEntry(distance: 0.0, nodeId: origin.id));

    // ---- main loop ---------------------------------------------------------
    while (pq.isNotEmpty) {
      final entry = pq.removeFirst();
      final u = entry.nodeId;
      final d = entry.distance;

      // Early exit: destination dequeued → its distance is finalised.
      if (u == destination.id) break;

      // Stale entry: a shorter path to u was already processed.
      if (d > dist[u]!) continue;

      // Relax neighbours.
      final neighbours = _adjacencyList[u] ?? [];
      for (final edge in neighbours) {
        final v = edge.targetNodeId;
        final alt = dist[u]! + edge.weight;
        if (alt < dist[v]!) {
          dist[v] = alt;
          prev[v] = u;
          pq.add(_DijkstraEntry(distance: alt, nodeId: v));
        }
      }
    }

    // ---- check reachability ------------------------------------------------
    if (dist[destination.id]!.isInfinite) return null;

    // ---- reconstruct path --------------------------------------------------
    final reversePath = <GraphNode>[];
    String? current = destination.id;
    while (current != null) {
      reversePath.add(_graphNodes[current]!);
      current = prev[current];
    }
    final path = reversePath.reversed.toList();

    // ---- build turn instructions -------------------------------------------
    // turnInstructions[i] describes the move from path[i] to path[i+1].
    final instructions = <String>[];
    for (int i = 0; i < path.length - 1; i++) {
      instructions.add('Head towards ${path[i + 1].name}');
    }

    return RouteModel(
      nodes: path,
      turnInstructions: instructions,
      totalDistanceMeters: dist[destination.id]!,
      destination: destination,
    );
  }

  // ---- helpers --------------------------------------------------------------

  /// Computes the Haversine great-circle distance in **metres** between two
  /// points expressed in decimal degrees.
  ///
  /// Formula:
  /// ```
  /// a = sin²(Δlat/2) + cos(lat1) · cos(lat2) · sin²(Δlon/2)
  /// c = 2 · atan2(√a, √(1 − a))
  /// d = R · c          where R = 6 371 000 m
  /// ```
  static double _haversineMeters(
    double lat1Deg,
    double lon1Deg,
    double lat2Deg,
    double lon2Deg,
  ) {
    const double earthRadiusMeters = 6371000.0;

    final double lat1 = _toRadians(lat1Deg);
    final double lat2 = _toRadians(lat2Deg);
    final double deltaLat = _toRadians(lat2Deg - lat1Deg);
    final double deltaLon = _toRadians(lon2Deg - lon1Deg);

    final double sinHalfDeltaLat = math.sin(deltaLat / 2);
    final double sinHalfDeltaLon = math.sin(deltaLon / 2);

    final double a =
        sinHalfDeltaLat * sinHalfDeltaLat +
        math.cos(lat1) *
            math.cos(lat2) *
            sinHalfDeltaLon *
            sinHalfDeltaLon;

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  // ---- accessors (used by tests and external subscribers) -------------------

  /// Exposes the internal node map for testing purposes.
  Map<String, GraphNode> get graphNodes => Map.unmodifiable(_graphNodes);

  /// Exposes the adjacency list for testing purposes.
  AdjacencyList get adjacencyList =>
      _adjacencyList.map((k, v) => MapEntry(k, List.unmodifiable(v)));

  /// Computes the Haversine distance between two points (exposed for tests).
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      _haversineMeters(lat1, lon1, lat2, lon2);

  /// Subscribes to Realtime location AND edge updates from the repository
  /// and rebuilds the graph whenever either table changes (Requirement 4.5).
  ///
  /// Each stream emits the full table contents, so the rebuild pairs the
  /// fresh event payload with the latest known snapshot of the other table.
  /// [rebuildPending] is set as soon as an event arrives (before the
  /// complementary fetch completes) so [computeRouteAsync] queues requests
  /// against the stale graph instead of running them.
  void subscribeToRealtimeUpdates(CampusRepository repository) {
    _edgesSubscription ??= repository.edgesStream().listen((updatedEdges) {
      rebuildPending = true;
      repository.fetchLocations().then((locs) {
        buildGraph(locs, updatedEdges);
      }).catchError((_) {
        // Offline: rebuild with the fresh edges + last-known locations so
        // the graph still reflects the edge change.
        buildGraph(_latestLocations, updatedEdges);
      });
    }, onError: (_) {
      // Silently handle stream errors
    });

    _locationsSubscription ??=
        repository.locationsStream().listen((updatedLocations) {
      rebuildPending = true;
      repository.fetchEdges().then((edges) {
        buildGraph(updatedLocations, edges);
      }).catchError((_) {
        // Offline: rebuild with the fresh locations + last-known edges.
        buildGraph(updatedLocations, _latestEdges);
      });
    }, onError: (_) {
      // Silently handle stream errors
    });
  }

  /// Cancels Realtime subscriptions. Safe to call more than once.
  Future<void> dispose() async {
    await _edgesSubscription?.cancel();
    await _locationsSubscription?.cancel();
    _edgesSubscription = null;
    _locationsSubscription = null;
  }
}

// ---------------------------------------------------------------------------
// _DijkstraEntry — priority-queue entry for Dijkstra's algorithm
// ---------------------------------------------------------------------------

/// An immutable (distance, nodeId) pair inserted into [HeapPriorityQueue]
/// during [RoutingService.computeRoute].
class _DijkstraEntry {
  const _DijkstraEntry({required this.distance, required this.nodeId});

  /// Best-known tentative distance from the source node to [nodeId].
  final double distance;

  /// The campus graph node this entry represents.
  final String nodeId;
}
