// Feature: campus-map-navigation, Property 2: Route Symmetry
//
// **Validates: Requirements 5.8**
//
// For any two distinct campus graph nodes A and B, where both
// computeRoute(A, B) and computeRoute(B, A) return non-null routes, the
// total distance of the route from A to B SHALL equal the total distance of
// the route from B to A when all edges are undirected (i.e., every edge is
// represented in both directions with equal weight).

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [LocationModel] with an index-based unique ID and a fixed
/// coordinate spread so Haversine distances between nodes are distinct.
LocationModel _makeLocation(int index) {
  return LocationModel(
    id: 'node-$index',
    name: 'Node $index',
    department: '',
    lat: 7.0 + index * 0.001,
    lng: 5.0 + index * 0.001,
    hours: '',
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Builds a chain-topology edge list that guarantees full connectivity:
/// node-0 ↔ node-1 ↔ node-2 ↔ … ↔ node-(n-1).
///
/// A chain means there is exactly one path between any pair of nodes, so
/// route results are deterministic and both directions must use the same
/// path (reversed), making symmetry easy to verify.
List<EdgeModel> _chainEdges(
  List<LocationModel> locations,
  List<double> distances,
) {
  final edges = <EdgeModel>[];
  for (var i = 0; i < locations.length - 1; i++) {
    edges.add(EdgeModel(
      id: 'edge-$i',
      fromLocationId: locations[i].id,
      toLocationId: locations[i + 1].id,
      distanceMeters: distances[i],
    ));
  }
  return edges;
}

/// Builds a random-edge list on top of a guaranteed chain backbone.
///
/// The chain ensures connectivity; the extra edges add route variety for
/// a richer symmetry test (Dijkstra may prefer shorter multi-hop paths).
List<EdgeModel> _chainPlusRandomEdges(
  List<LocationModel> locations,
  List<double> chainDistances,
  List<(int, int, double)> extraEdgeTriples,
) {
  final edges = _chainEdges(locations, chainDistances);

  var extraIndex = edges.length;
  for (final (fromRaw, toRaw, dist) in extraEdgeTriples) {
    final n = locations.length;
    final from = fromRaw.clamp(0, n - 1);
    var to = toRaw.clamp(0, n - 1);
    // Avoid self-loops.
    if (from == to) to = (to + 1) % n;
    edges.add(EdgeModel(
      id: 'edge-extra-$extraIndex',
      fromLocationId: locations[from].id,
      toLocationId: locations[to].id,
      distanceMeters: dist,
    ));
    extraIndex++;
  }

  return edges;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 2: Route Symmetry on Undirected Graphs', () {
    // -------------------------------------------------------------------------
    // P2a — Chain topology: all pairs are reachable; both directions must
    //        return equal totalDistanceMeters.
    // -------------------------------------------------------------------------
    property(
      'P2a – chain graph: computeRoute(A,B).distance == computeRoute(B,A).distance '
      'for all node pairs',
      () {
        forAll(
          combine3(
            // 2–15 nodes (chain needs at least 2).
            integer(min: 2, max: 15),
            // Edge distances for the chain (one fewer than node count).
            list(
              float(min: 1.0, max: 5000.0, nan: false, infinity: false),
              minLength: 1,
              maxLength: 14,
            ),
            // Two node indices to pick as A and B.
            combine2(
              integer(min: 0, max: 14),
              integer(min: 0, max: 14),
            ),
          ),
          (data) {
            final (nodeCount, rawDistances, indexPair) = data;
            final (rawA, rawB) = indexPair;

            // Build locations.
            final locations = List.generate(nodeCount, _makeLocation);

            // Ensure we have enough distances for the chain
            // (chain needs nodeCount-1 distances).
            final chainLength = nodeCount - 1;
            final distances = List.generate(
              chainLength,
              (i) =>
                  i < rawDistances.length ? rawDistances[i].abs() + 1.0 : 50.0,
            );

            final edges = _chainEdges(locations, distances);

            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Pick two distinct node indices.
            final indexA = rawA.clamp(0, nodeCount - 1);
            var indexB = rawB.clamp(0, nodeCount - 1);
            if (indexA == indexB) {
              indexB = (indexB + 1) % nodeCount;
            }

            final nodeA = service.graphNodes['node-$indexA']!;
            final nodeB = service.graphNodes['node-$indexB']!;

            final routeAB = service.computeRoute(nodeA, nodeB);
            final routeBA = service.computeRoute(nodeB, nodeA);

            // On a fully-connected chain both routes must be non-null.
            expect(routeAB, isNotNull,
                reason: 'computeRoute(A→B) should be reachable on a chain graph');
            expect(routeBA, isNotNull,
                reason: 'computeRoute(B→A) should be reachable on a chain graph');

            // Core symmetry assertion.
            expect(
              routeAB!.totalDistanceMeters,
              closeTo(routeBA!.totalDistanceMeters, 1e-9),
              reason:
                  'totalDistanceMeters A→B (${routeAB.totalDistanceMeters}) '
                  'must equal B→A (${routeBA.totalDistanceMeters}) '
                  'for an undirected graph',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P2b — Chain + random extra edges: Dijkstra may choose a shorter
    //        multi-hop path; symmetry must still hold.
    // -------------------------------------------------------------------------
    property(
      'P2b – graph with extra shortcut edges: '
      'computeRoute(A,B).distance == computeRoute(B,A).distance',
      () {
        forAll(
          combine3(
            // 3–10 nodes.
            integer(min: 3, max: 10),
            // Chain distances (nodeCount-1 entries generated separately).
            list(
              float(min: 10.0, max: 2000.0, nan: false, infinity: false),
              minLength: 2,
              maxLength: 9,
            ),
            // 1–6 extra (random) shortcut edges.
            list(
              combine3(
                integer(min: 0, max: 9),
                integer(min: 0, max: 9),
                float(min: 1.0, max: 3000.0, nan: false, infinity: false),
              ),
              minLength: 1,
              maxLength: 6,
            ),
          ),
          (data) {
            final (nodeCount, rawChainDists, extraTriples) = data;

            final locations = List.generate(nodeCount, _makeLocation);

            // Build chain distances (ensure positive, pad/truncate as needed).
            final chainLength = nodeCount - 1;
            final chainDists = List.generate(
              chainLength,
              (i) => i < rawChainDists.length
                  ? rawChainDists[i].abs() + 1.0
                  : 100.0,
            );

            final edges = _chainPlusRandomEdges(
              locations,
              chainDists,
              extraTriples,
            );

            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Test all unique node pairs in the graph.
            for (var i = 0; i < nodeCount; i++) {
              for (var j = i + 1; j < nodeCount; j++) {
                final nodeA = service.graphNodes['node-$i']!;
                final nodeB = service.graphNodes['node-$j']!;

                final routeAB = service.computeRoute(nodeA, nodeB);
                final routeBA = service.computeRoute(nodeB, nodeA);

                // Both must have the same reachability status.
                expect(
                  routeAB == null,
                  equals(routeBA == null),
                  reason:
                      'Reachability must be symmetric: '
                      'A→B is ${routeAB == null ? 'null' : 'non-null'} but '
                      'B→A is ${routeBA == null ? 'null' : 'non-null'} '
                      'for nodes node-$i and node-$j',
                );

                if (routeAB == null) continue; // unreachable pair — skip

                // Core symmetry assertion.
                expect(
                  routeAB.totalDistanceMeters,
                  closeTo(routeBA!.totalDistanceMeters, 1e-9),
                  reason:
                      'totalDistanceMeters must be equal in both directions: '
                      'A→B = ${routeAB.totalDistanceMeters}, '
                      'B→A = ${routeBA.totalDistanceMeters} '
                      'for nodes node-$i and node-$j',
                );
              }
            }
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P2c — Disconnected graph: symmetry of reachability must hold
    //        (if A cannot reach B, then B cannot reach A either).
    // -------------------------------------------------------------------------
    property(
      'P2c – disconnected graph: reachability is symmetric '
      '(null ↔ null, non-null ↔ non-null)',
      () {
        forAll(
          // Two separate chains of 2–5 nodes each, with no bridge between them.
          combine2(
            integer(min: 2, max: 5), // size of component 1
            integer(min: 2, max: 5), // size of component 2
          ),
          (data) {
            final (sizeA, sizeB) = data;
            final totalNodes = sizeA + sizeB;

            final locations = List.generate(totalNodes, _makeLocation);

            // Build two isolated chains with a gap between them.
            // Component 1: node-0 … node-(sizeA-1)
            // Component 2: node-sizeA … node-(totalNodes-1)
            final edges = <EdgeModel>[];
            for (var i = 0; i < sizeA - 1; i++) {
              edges.add(EdgeModel(
                id: 'chain1-edge-$i',
                fromLocationId: locations[i].id,
                toLocationId: locations[i + 1].id,
                distanceMeters: 100.0,
              ));
            }
            for (var i = sizeA; i < totalNodes - 1; i++) {
              edges.add(EdgeModel(
                id: 'chain2-edge-$i',
                fromLocationId: locations[i].id,
                toLocationId: locations[i + 1].id,
                distanceMeters: 100.0,
              ));
            }

            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Check every pair across components (must be unreachable in both
            // directions) and within components (must be reachable symmetrically).
            for (var i = 0; i < totalNodes; i++) {
              for (var j = i + 1; j < totalNodes; j++) {
                final nodeA = service.graphNodes['node-$i']!;
                final nodeB = service.graphNodes['node-$j']!;

                final routeAB = service.computeRoute(nodeA, nodeB);
                final routeBA = service.computeRoute(nodeB, nodeA);

                // Reachability must be symmetric regardless of component.
                expect(
                  routeAB == null,
                  equals(routeBA == null),
                  reason:
                      'Reachability symmetry violated for nodes '
                      'node-$i and node-$j: '
                      'A→B=${routeAB == null ? 'null' : 'non-null'}, '
                      'B→A=${routeBA == null ? 'null' : 'non-null'}',
                );

                if (routeAB == null) continue;

                // Within-component pairs must also have equal distances.
                expect(
                  routeAB.totalDistanceMeters,
                  closeTo(routeBA!.totalDistanceMeters, 1e-9),
                  reason:
                      'Distance symmetry violated for nodes node-$i and node-$j: '
                      'A→B=${routeAB.totalDistanceMeters}, '
                      'B→A=${routeBA.totalDistanceMeters}',
                );
              }
            }
          },
          maxExamples: 100,
        );
      },
    );
  });
}
