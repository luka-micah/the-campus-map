import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/graph_node.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/data/campus_repository.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LocationModel _loc(String id, String name, {double lat = 0.0, double lng = 0.0}) =>
    LocationModel(
      id: id,
      name: name,
      department: '',
      lat: lat,
      lng: lng,
      hours: '',
      createdAt: DateTime(2024),
    );

EdgeModel _edge(String id, String from, String to, double dist) =>
    EdgeModel(id: id, fromLocationId: from, toLocationId: to, distanceMeters: dist);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late RoutingService sut;

  setUp(() {
    sut = RoutingService();
  });

  // ---- buildGraph ----------------------------------------------------------

  group('buildGraph', () {
    test('zero nodes → graphNodes empty, adjacencyList empty', () {
      sut.buildGraph([], []);

      expect(sut.graphNodes, isEmpty);
      expect(sut.adjacencyList, isEmpty);
    });

    test('single node, no edges → one GraphNode, empty adjacency entry', () {
      sut.buildGraph([_loc('a', 'Alpha')], []);

      expect(sut.graphNodes, hasLength(1));
      expect(sut.graphNodes.containsKey('a'), isTrue);
      expect(sut.adjacencyList['a'], isEmpty);
    });

    test(
        'single node has correct id, name, lat, lng after buildGraph', () {
      sut.buildGraph([_loc('a', 'Alpha', lat: 7.1, lng: 5.2)], []);

      final node = sut.graphNodes['a']!;
      expect(node.id, 'a');
      expect(node.name, 'Alpha');
      expect(node.lat, 7.1);
      expect(node.lng, 5.2);
    });

    test('two disconnected nodes, no edges → both present, no adjacency entries',
        () {
      sut.buildGraph([_loc('a', 'Alpha'), _loc('b', 'Beta')], []);

      expect(sut.graphNodes, hasLength(2));
      expect(sut.adjacencyList['a'], isEmpty);
      expect(sut.adjacencyList['b'], isEmpty);
    });

    test(
        'malformed edge referencing non-existent IDs → does not throw, skips '
        'that edge', () {
      sut.buildGraph(
        [_loc('a', 'Alpha')],
        [_edge('e1', 'a', 'ghost', 100.0)], // 'ghost' does not exist
      );

      // Must not throw; the adjacency list for 'a' must remain empty.
      expect(sut.adjacencyList['a'], isEmpty);
    });

    test(
        'malformed edge mixed with valid edges → only well-formed edge is added',
        () {
      sut.buildGraph(
        [_loc('a', 'Alpha'), _loc('b', 'Beta')],
        [
          _edge('e1', 'a', 'ghost', 50.0), // malformed
          _edge('e2', 'a', 'b', 200.0),    // valid
        ],
      );

      // 'a' → 'b' must exist with weight 200.0.
      final aNeighbours = sut.adjacencyList['a']!;
      expect(aNeighbours, hasLength(1));
      expect(aNeighbours.first.targetNodeId, 'b');
      expect(aNeighbours.first.weight, 200.0);

      // Reverse direction must also exist.
      final bNeighbours = sut.adjacencyList['b']!;
      expect(bNeighbours, hasLength(1));
      expect(bNeighbours.first.targetNodeId, 'a');
    });

    test('rebuildPending is false after a successful buildGraph call', () {
      sut.buildGraph([_loc('a', 'Alpha')], []);

      expect(sut.rebuildPending, isFalse);
    });
  });

  // ---- computeRoute --------------------------------------------------------

  group('computeRoute', () {
    test('disconnected nodes → returns null', () {
      sut.buildGraph([_loc('a', 'Alpha'), _loc('b', 'Beta')], []);

      final nodeA = sut.graphNodes['a']!;
      final nodeB = sut.graphNodes['b']!;

      expect(sut.computeRoute(nodeA, nodeB), isNull);
    });

    test('origin == destination → returns route with single node, zero distance',
        () {
      sut.buildGraph([_loc('a', 'Alpha')], []);

      final nodeA = sut.graphNodes['a']!;
      final route = sut.computeRoute(nodeA, nodeA);

      expect(route, isNotNull);
      expect(route!.nodes, hasLength(1));
      expect(route.nodes.first.id, 'a');
      expect(route.totalDistanceMeters, 0.0);
      expect(route.turnInstructions, isEmpty);
    });

    test('simple 3-node chain A→B→C → correct path and total distance', () {
      // A ─100m─ B ─150m─ C
      sut.buildGraph(
        [_loc('a', 'Alpha'), _loc('b', 'Beta'), _loc('c', 'Gamma')],
        [
          _edge('e1', 'a', 'b', 100.0),
          _edge('e2', 'b', 'c', 150.0),
        ],
      );

      final nodeA = sut.graphNodes['a']!;
      final nodeC = sut.graphNodes['c']!;
      final route = sut.computeRoute(nodeA, nodeC);

      expect(route, isNotNull);
      expect(route!.nodes.map((n) => n.id).toList(), ['a', 'b', 'c']);
      expect(route.totalDistanceMeters, closeTo(250.0, 1e-9));
    });

    test(
        '3-node chain: computeRoute picks shortest path when shortcut available',
        () {
      // A ─100m─ B ─150m─ C
      //  └──────────────── 400m ──────────────┘  (direct, longer)
      sut.buildGraph(
        [_loc('a', 'Alpha'), _loc('b', 'Beta'), _loc('c', 'Gamma')],
        [
          _edge('e1', 'a', 'b', 100.0),
          _edge('e2', 'b', 'c', 150.0),
          _edge('e3', 'a', 'c', 400.0),
        ],
      );

      final nodeA = sut.graphNodes['a']!;
      final nodeC = sut.graphNodes['c']!;
      final route = sut.computeRoute(nodeA, nodeC);

      // Shortest path is A→B→C = 250 m, not direct 400 m.
      expect(route!.totalDistanceMeters, closeTo(250.0, 1e-9));
    });

    test('node not in graph → returns null', () {
      sut.buildGraph([_loc('a', 'Alpha')], []);

      final phantom = const GraphNode(id: 'z', name: 'Ghost', lat: 0, lng: 0);
      final nodeA = sut.graphNodes['a']!;

      expect(sut.computeRoute(nodeA, phantom), isNull);
      expect(sut.computeRoute(phantom, nodeA), isNull);
    });
  });

  // ---- Requirement 4.5: rebuild on data change + queued requests ----------

  group('Requirement 4.5 rebuild + request queue', () {
    test('computeRouteAsync resolves immediately when no rebuild is pending',
        () async {
      sut.buildGraph(
        [_loc('a', 'Alpha'), _loc('b', 'Beta')],
        [_edge('e1', 'a', 'b', 100.0)],
      );

      final route = await sut.computeRouteAsync(
        sut.graphNodes['a']!,
        sut.graphNodes['b']!,
      );

      expect(route, isNotNull);
      expect(route!.totalDistanceMeters, closeTo(100.0, 1e-9));
      expect(sut.rebuildPending, isFalse);
    });

    test('request arriving during rebuild is queued and uses the fresh graph',
        () async {
      // Start disconnected: no path a → b.
      sut.buildGraph([_loc('a', 'Alpha'), _loc('b', 'Beta')], []);
      expect(
        sut.computeRoute(sut.graphNodes['a']!, sut.graphNodes['b']!),
        isNull,
      );

      // Simulate a repository event arriving (rebuild pending).
      sut.rebuildPending = true;
      final pending = sut.computeRouteAsync(
        const GraphNode(id: 'a', name: 'Alpha', lat: 0, lng: 0),
        const GraphNode(id: 'b', name: 'Beta', lat: 0, lng: 0),
      );

      // Rebuild with the new edge, then the queued request must resolve
      // against the FRESH graph (path exists, 100 m).
      sut.buildGraph(
        [_loc('a', 'Alpha'), _loc('b', 'Beta')],
        [_edge('e1', 'a', 'b', 100.0)],
      );

      final route = await pending;
      expect(route, isNotNull);
      expect(route!.nodes.map((n) => n.id).toList(), ['a', 'b']);
      expect(route.totalDistanceMeters, closeTo(100.0, 1e-9));
      expect(sut.rebuildPending, isFalse);
    });

    test('locationsStream event rebuilds the graph without manual buildGraph',
        () async {
      final repo = _FakeCampusRepository(
        locations: [_loc('a', 'Alpha')],
        edges: [],
      );
      sut.buildGraph(repo.locations, repo.edges);
      sut.subscribeToRealtimeUpdates(repo);
      expect(sut.graphNodes.containsKey('b'), isFalse);

      // Admin adds location 'b' + edge a→b.
      repo.locations = [_loc('a', 'Alpha'), _loc('b', 'Beta')];
      repo.edges = [_edge('e1', 'a', 'b', 50.0)];
      repo.emitLocations(repo.locations);

      // Allow stream event + async fetch to complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sut.graphNodes.containsKey('b'), isTrue);
      final route = sut.computeRoute(
        sut.graphNodes['a']!,
        sut.graphNodes['b']!,
      );
      expect(route, isNotNull);
      expect(route!.totalDistanceMeters, closeTo(50.0, 1e-9));
      await sut.dispose();
    });

    test('edgesStream event rebuilds the graph without manual buildGraph',
        () async {
      final repo = _FakeCampusRepository(
        locations: [_loc('a', 'Alpha'), _loc('b', 'Beta')],
        edges: [],
      );
      sut.buildGraph(repo.locations, repo.edges);
      sut.subscribeToRealtimeUpdates(repo);
      expect(
        sut.computeRoute(sut.graphNodes['a']!, sut.graphNodes['b']!),
        isNull,
      );

      // Admin adds edge a→b.
      repo.edges = [_edge('e1', 'a', 'b', 75.0)];
      repo.emitEdges(repo.edges);

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final route = sut.computeRoute(
        sut.graphNodes['a']!,
        sut.graphNodes['b']!,
      );
      expect(route, isNotNull);
      expect(route!.totalDistanceMeters, closeTo(75.0, 1e-9));
      await sut.dispose();
    });
  });

  // ---- nearestNode ---------------------------------------------------------

  group('nearestNode', () {
    test('single-node graph → always returns that node', () {
      sut.buildGraph([_loc('a', 'Alpha', lat: 7.1, lng: 5.2)], []);

      final result = sut.nearestNode(const LatLng(10.0, 20.0));

      expect(result.id, 'a');
    });

    test('empty graph → throws StateError', () {
      sut.buildGraph([], []);

      expect(
        () => sut.nearestNode(const LatLng(0.0, 0.0)),
        throwsA(isA<StateError>()),
      );
    });

    test('returns the node with minimum Haversine distance to query position',
        () {
      // Place three nodes at known positions.
      // Node 'b' is the closest to the query.
      sut.buildGraph(
        [
          _loc('a', 'Alpha', lat: 0.0, lng: 0.0),   // far
          _loc('b', 'Beta', lat: 7.0, lng: 5.0),    // closest to query
          _loc('c', 'Gamma', lat: 20.0, lng: 30.0), // even farther
        ],
        [],
      );

      // Query close to 'b'.
      final result = sut.nearestNode(const LatLng(7.001, 5.001));

      expect(result.id, 'b');
    });

    test(
        'nearestNode result has Haversine distance ≤ every other node distance',
        () {
      sut.buildGraph(
        [
          _loc('a', 'Alpha', lat: 0.0, lng: 0.0),
          _loc('b', 'Beta', lat: 7.0, lng: 5.0),
          _loc('c', 'Gamma', lat: 20.0, lng: 30.0),
        ],
        [],
      );

      const query = LatLng(7.5, 5.5);
      final nearest = sut.nearestNode(query);
      final nearestDist = RoutingService.haversineMeters(
        query.latitude,
        query.longitude,
        nearest.lat,
        nearest.lng,
      );

      for (final node in sut.graphNodes.values) {
        final d = RoutingService.haversineMeters(
          query.latitude,
          query.longitude,
          node.lat,
          node.lng,
        );
        expect(nearestDist, lessThanOrEqualTo(d));
      }
    });
  });
}

/// In-memory [CampusRepository] for Requirement 4.5 tests.
///
/// Streams are broadcast [StreamController]s driven manually via [emitLocations]
/// / [emitEdges], mimicking Supabase Realtime table-change events.
class _FakeCampusRepository implements CampusRepository {
  _FakeCampusRepository({required this.locations, required this.edges});

  List<LocationModel> locations;
  List<EdgeModel> edges;

  @override
  bool get isOfflineMode => false;

  final _locationsCtrl = StreamController<List<LocationModel>>.broadcast();
  final _edgesCtrl = StreamController<List<EdgeModel>>.broadcast();

  void emitLocations(List<LocationModel> value) =>
      _locationsCtrl.add(List.of(value));

  void emitEdges(List<EdgeModel> value) => _edgesCtrl.add(List.of(value));

  @override
  Future<List<LocationModel>> fetchLocations() async => List.of(locations);

  @override
  Future<List<EdgeModel>> fetchEdges() async => List.of(edges);

  @override
  Stream<List<LocationModel>> locationsStream() => _locationsCtrl.stream;

  @override
  Stream<List<EdgeModel>> edgesStream() => _edgesCtrl.stream;

  @override
  Future<void> insertLocation(LocationModel loc) async {
    locations.add(loc);
  }

  @override
  Future<void> updateLocation(LocationModel loc) async {}

  @override
  Future<void> deleteLocation(String id) async {
    locations.removeWhere((l) => l.id == id);
  }

  @override
  Future<List<LocationModel>> searchLocations(String query) async {
    final q = query.toLowerCase();
    return locations.where((l) => l.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<void> insertEdge(EdgeModel edge) async {
    edges.add(edge);
  }

  @override
  Future<void> updateEdge(EdgeModel edge) async {
    final index = edges.indexWhere((e) => e.id == edge.id);
    if (index != -1) edges[index] = edge;
  }

  @override
  Future<void> deleteEdge(String id) async {
    edges.removeWhere((e) => e.id == id);
  }
}
