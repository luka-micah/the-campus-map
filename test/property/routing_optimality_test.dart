// Feature: campus-map-navigation, Property 3: Dijkstra Optimality
//
// **Validates: Requirements 5.3**
//
// For any valid origin–destination pair on a randomly generated graph, the
// total distance of the route returned by RoutingService.computeRoute SHALL be
// less than or equal to the total distance of every other valid (simple) path
// between the same endpoints.
//
// Verification strategy:
//   • Generate small random graphs (3–10 nodes) with random positive-weight
//     edges so that brute-force enumeration of all simple paths is tractable.
//   • Run Dijkstra via computeRoute(origin, destination).
//   • Enumerate ALL simple paths from origin to destination using a recursive
//     DFS that tracks visited nodes to avoid cycles.
//   • Assert: dijkstraDistance ≤ weight of every brute-force path.
//   • When Dijkstra returns null, brute-force must also find no paths
//     (no path consistency).
//   • Runs 100 iterations.

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [LocationModel] with a deterministic ID from [index].
/// Coordinates are spread slightly so Haversine distances are non-zero.
LocationModel _makeLocation(int index) {
  return LocationModel(
    id: 'node-$index',
    name: 'Node $index',
    department: '',
    lat: 7.0 + index * 0.01,
    lng: 5.0 + index * 0.01,
    hours: '',
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Computes the total weight of a path described by a list of node IDs,
/// using the adjacency list exposed by [RoutingService].
///
/// Returns `null` if any consecutive pair has no connecting edge (should not
/// happen for paths produced by [_allSimplePaths]).
double? _pathWeight(
  List<String> path,
  Map<String, List<dynamic>> adjacencyList,
) {
  double total = 0.0;
  for (int i = 0; i < path.length - 1; i++) {
    final edges = adjacencyList[path[i]];
    if (edges == null) return null;
    // Find the edge connecting path[i] → path[i+1].
    final matching = edges.where((e) => e.targetNodeId == path[i + 1]);
    if (matching.isEmpty) return null;
    // Use the minimum weight if multiple parallel edges exist.
    total += matching.map((e) => e.weight as double).reduce(
      (a, b) => a < b ? a : b,
    );
  }
  return total;
}

/// Enumerates ALL simple paths from [startId] to [endId] in the undirected
/// graph described by [adjacencyList].
///
/// A simple path visits each node at most once, so cycle-free by construction.
/// For graphs with 3–10 nodes the search space is always finite and small.
List<List<String>> _allSimplePaths(
  String startId,
  String endId,
  Map<String, List<dynamic>> adjacencyList,
) {
  final results = <List<String>>[];

  void dfs(String current, List<String> visited) {
    if (current == endId) {
      results.add(List<String>.from(visited));
      return;
    }
    final neighbours = adjacencyList[current] ?? [];
    for (final edge in neighbours) {
      final next = edge.targetNodeId as String;
      if (!visited.contains(next)) {
        visited.add(next);
        dfs(next, visited);
        visited.removeLast();
      }
    }
  }

  dfs(startId, [startId]);
  return results;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 3: Dijkstra Optimality', () {
    // -------------------------------------------------------------------------
    // P3 — main optimality assertion:
    //   Dijkstra's total distance ≤ every simple-path distance for the same
    //   origin–destination pair.
    // -------------------------------------------------------------------------
    property(
      'P3 – Dijkstra returns the shortest path among all simple paths',
      () {
        forAll(
          combine3(
            // Number of nodes: 3–10 (small enough for brute-force enumeration).
            integer(min: 3, max: 10),
            // Edge list: each entry is (fromIndex, toIndex, distance).
            list(
              combine3(
                integer(min: 0, max: 9), // fromIndex (clamped to nodeCount)
                integer(min: 0, max: 9), // toIndex   (clamped to nodeCount)
                float(
                  min: 1.0,
                  max: 5000.0,
                  nan: false,
                  infinity: false,
                ), // distanceMeters
              ),
              minLength: 2,
              maxLength: 20,
            ),
            // Origin and destination: pick two distinct indices.
            integer(min: 0, max: 9),
          ),
          (data) {
            final (nodeCount, edgeTriples, rawOriginIdx) = data;

            // Build locations.
            final locations = List.generate(nodeCount, _makeLocation);

            // Build edges — skip self-loops so every edge is meaningful.
            final edges = <EdgeModel>[];
            for (var i = 0; i < edgeTriples.length; i++) {
              final (fromRaw, toRaw, dist) = edgeTriples[i];
              final from = fromRaw.clamp(0, nodeCount - 1);
              var to = toRaw.clamp(0, nodeCount - 1);
              if (from == to) to = (to + 1) % nodeCount;
              edges.add(EdgeModel(
                id: 'edge-$i',
                fromLocationId: locations[from].id,
                toLocationId: locations[to].id,
                distanceMeters: dist,
              ));
            }

            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Choose two distinct node indices as origin and destination.
            final originIdx = rawOriginIdx.clamp(0, nodeCount - 1);
            final destIdx = (originIdx + 1) % nodeCount;

            final originNode = service.graphNodes[locations[originIdx].id]!;
            final destNode = service.graphNodes[locations[destIdx].id]!;

            // Run Dijkstra.
            final route = service.computeRoute(originNode, destNode);

            // Enumerate all simple paths using brute-force DFS.
            final allPaths = _allSimplePaths(
              originNode.id,
              destNode.id,
              service.adjacencyList,
            );

            if (route == null) {
              // No path — brute-force must also find zero paths.
              expect(
                allPaths,
                isEmpty,
                reason:
                    'Dijkstra returned null (no path) but brute-force found '
                    '${allPaths.length} simple path(s) from '
                    '${originNode.id} to ${destNode.id}. '
                    'The graph is undirected so a brute-force path implies '
                    'Dijkstra should also find one.',
              );
            } else {
              // Path exists — brute-force must also find at least one path.
              expect(
                allPaths.isNotEmpty,
                isTrue,
                reason:
                    'Dijkstra found a route but brute-force found no simple '
                    'paths from ${originNode.id} to ${destNode.id}.',
              );

              final dijkstraDist = route.totalDistanceMeters;

              // Assert: Dijkstra distance ≤ every brute-force path distance.
              for (final path in allPaths) {
                final bfWeight = _pathWeight(path, service.adjacencyList);

                // bfWeight should never be null for paths produced by
                // _allSimplePaths (all edges exist by construction).
                expect(
                  bfWeight,
                  isNotNull,
                  reason:
                      'Could not compute weight for brute-force path $path — '
                      'missing edge in adjacency list.',
                );

                expect(
                  dijkstraDist,
                  lessThanOrEqualTo(bfWeight! + 1e-9),
                  reason:
                      'Dijkstra returned distance $dijkstraDist m, but '
                      'brute-force path $path has weight $bfWeight m — '
                      'Dijkstra must return the optimal (minimum) distance.',
                );
              }
            }
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P3 edge-case — single-edge graph: Dijkstra must use that edge directly.
    // -------------------------------------------------------------------------
    property(
      'P3 edge-case – single edge between origin and destination is optimal',
      () {
        forAll(
          float(min: 1.0, max: 50000.0, nan: false, infinity: false),
          (dist) {
            // Three nodes: A — B — C.  Only edges A→B and B→C exist.
            // Route A→C must go through B with total = A→B + B→C.
            // But here we test A→B: only one path exists, Dijkstra must use it.
            final locations = List.generate(3, _makeLocation);

            final edges = [
              EdgeModel(
                id: 'e0',
                fromLocationId: locations[0].id,
                toLocationId: locations[1].id,
                distanceMeters: dist,
              ),
              EdgeModel(
                id: 'e1',
                fromLocationId: locations[1].id,
                toLocationId: locations[2].id,
                distanceMeters: dist * 0.5,
              ),
            ];

            final service = RoutingService();
            service.buildGraph(locations, edges);

            final originNode = service.graphNodes[locations[0].id]!;
            final destNode = service.graphNodes[locations[1].id]!;

            final route = service.computeRoute(originNode, destNode);

            expect(route, isNotNull, reason: 'Edge A→B must yield a route');
            expect(
              route!.totalDistanceMeters,
              closeTo(dist, 1e-9),
              reason:
                  'Only one path A→B exists with distance $dist; '
                  'Dijkstra must return exactly that distance.',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P3 edge-case — two parallel paths: Dijkstra must choose the shorter one.
    // -------------------------------------------------------------------------
    property(
      'P3 edge-case – Dijkstra chooses shorter of two parallel paths',
      () {
        forAll(
          combine2(
            float(min: 100.0, max: 5000.0, nan: false, infinity: false),
            float(min: 1.0, max: 99.0, nan: false, infinity: false),
          ),
          (data) {
            final (longDist, shortDist) = data;

            // Four nodes: A, B, C, D.
            //   Direct path:   A → D  (weight = longDist)
            //   Indirect path: A → B → C → D  (total = shortDist * 3)
            // When shortDist * 3 < longDist, the indirect path is shorter.
            final locations = List.generate(4, _makeLocation);

            final edges = [
              // Direct (longer) path A → D.
              EdgeModel(
                id: 'direct',
                fromLocationId: locations[0].id,
                toLocationId: locations[3].id,
                distanceMeters: longDist,
              ),
              // Indirect (shorter) path A → B → C → D.
              EdgeModel(
                id: 'ab',
                fromLocationId: locations[0].id,
                toLocationId: locations[1].id,
                distanceMeters: shortDist,
              ),
              EdgeModel(
                id: 'bc',
                fromLocationId: locations[1].id,
                toLocationId: locations[2].id,
                distanceMeters: shortDist,
              ),
              EdgeModel(
                id: 'cd',
                fromLocationId: locations[2].id,
                toLocationId: locations[3].id,
                distanceMeters: shortDist,
              ),
            ];

            final service = RoutingService();
            service.buildGraph(locations, edges);

            final originNode = service.graphNodes[locations[0].id]!;
            final destNode = service.graphNodes[locations[3].id]!;

            final route = service.computeRoute(originNode, destNode);

            expect(route, isNotNull, reason: 'At least one path A→D must exist');

            final indirectTotal = shortDist * 3;
            final expectedMin =
                indirectTotal < longDist ? indirectTotal : longDist;

            expect(
              route!.totalDistanceMeters,
              closeTo(expectedMin, 1e-9),
              reason:
                  'Direct path=$longDist, indirect path=${shortDist * 3}; '
                  'Dijkstra must return the minimum ($expectedMin).',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P3 edge-case — disconnected graph: Dijkstra returns null, brute-force
    //               also finds no path.
    // -------------------------------------------------------------------------
    test(
      'P3 edge-case – disconnected graph produces null route and no BF paths',
      () {
        // Two isolated pairs: {A, B} and {C, D}. No edge crosses the groups.
        final locations = List.generate(4, _makeLocation);

        final edges = [
          EdgeModel(
            id: 'e0',
            fromLocationId: locations[0].id,
            toLocationId: locations[1].id,
            distanceMeters: 100.0,
          ),
          EdgeModel(
            id: 'e1',
            fromLocationId: locations[2].id,
            toLocationId: locations[3].id,
            distanceMeters: 200.0,
          ),
        ];

        final service = RoutingService();
        service.buildGraph(locations, edges);

        // Try routing from group 1 (A) to group 2 (C) — no path should exist.
        final originNode = service.graphNodes[locations[0].id]!;
        final destNode = service.graphNodes[locations[2].id]!;

        final route = service.computeRoute(originNode, destNode);
        expect(route, isNull, reason: 'No path exists between isolated groups');

        final allPaths = _allSimplePaths(
          originNode.id,
          destNode.id,
          service.adjacencyList,
        );
        expect(
          allPaths,
          isEmpty,
          reason: 'Brute-force should also find no path between isolated groups',
        );
      },
    );
  });
}
