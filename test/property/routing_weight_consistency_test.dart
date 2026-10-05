// Feature: campus-map-navigation, Property 1: Route Weight Consistency
//
// **Validates: Requirements 5.7**
//
// For any valid origin–destination pair where a path exists in the campus
// graph, the total distance of the route returned by
// RoutingService.computeRoute SHALL equal the sum of the distanceMeters values
// of each consecutive edge in the route's node sequence.

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Graph fixture helpers
// ---------------------------------------------------------------------------

/// Creates a [LocationModel] with a deterministic unique ID derived from
/// [index] so that generated graphs never have accidental ID collisions.
LocationModel _makeLocation(int index) {
  return LocationModel(
    id: 'loc-$index',
    name: 'Node $index',
    department: '',
    lat: index * 0.001,   // spread nodes along a line so coords are distinct
    lng: index * 0.001,
    hours: '',
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Builds a *chain* topology connecting [locations] in order:
///
///   loc-0 —[w0]— loc-1 —[w1]— loc-2 —…— loc-(n-1)
///
/// This guarantees full connectivity: any two distinct nodes have a path
/// between them. Each edge weight is taken from [weights] (must have length
/// `locations.length - 1`).
List<EdgeModel> _chainEdges(
  List<LocationModel> locations,
  List<double> weights,
) {
  assert(weights.length == locations.length - 1);
  final edges = <EdgeModel>[];
  for (var i = 0; i < locations.length - 1; i++) {
    edges.add(EdgeModel(
      id: 'edge-$i',
      fromLocationId: locations[i].id,
      toLocationId: locations[i + 1].id,
      distanceMeters: weights[i],
    ));
  }
  return edges;
}

// ---------------------------------------------------------------------------
// Route verification helper
// ---------------------------------------------------------------------------

/// Returns the sum of edge weights along [route.nodes] by looking each
/// consecutive pair (nodes[i], nodes[i+1]) up in the adjacency list.
///
/// Throws if an expected edge is absent (which itself would be a bug in
/// [RoutingService.buildGraph] — caught as a test failure).
double _sumEdgesAlongRoute(
  RoutingService service,
  List<dynamic> routeNodes, // List<GraphNode>
) {
  final adj = service.adjacencyList;
  var total = 0.0;

  for (var i = 0; i < routeNodes.length - 1; i++) {
    final fromId = routeNodes[i].id as String;
    final toId = routeNodes[i + 1].id as String;

    final outgoing = adj[fromId];
    expect(
      outgoing,
      isNotNull,
      reason: 'adjacencyList[$fromId] must not be null',
    );

    final entry = outgoing!.where((e) => e.targetNodeId == toId);
    expect(
      entry.isNotEmpty,
      isTrue,
      reason:
          'adjacencyList[$fromId] must contain an entry targeting $toId '
          'for the consecutive nodes in the route',
    );

    total += entry.first.weight;
  }

  return total;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 1: Route Weight Consistency', () {
    // -------------------------------------------------------------------------
    // P1 – main property
    //
    // Generate a random connected chain graph (5–50 nodes) with random positive
    // edge weights. Pick a random origin and destination index. Assert that
    // route.totalDistanceMeters equals the sum of the adjacency-list weights
    // along the route's node sequence.
    // -------------------------------------------------------------------------
    property(
      'P1 – totalDistanceMeters equals sum of edge weights along route path',
      () {
        forAll(
          combine3(
            // Number of nodes: 5–50.
            integer(min: 5, max: 50),
            // Edge weights for (nodeCount - 1) chain edges, each 1–5000 m.
            list(
              float(min: 1.0, max: 5000.0, nan: false, infinity: false),
              minLength: 4,   // at least 4 weights for 5 nodes
              maxLength: 49,  // at most 49 weights for 50 nodes
            ),
            // Origin and destination: two distinct indices into [0, nodeCount).
            combine2(
              integer(min: 0, max: 49),
              integer(min: 0, max: 49),
            ),
          ),
          (data) {
            final (rawNodeCount, rawWeights, indexPair) = data;
            final (rawOriginIdx, rawDestIdx) = indexPair;

            // Clamp node count to valid range and ensure we have enough weights.
            final nodeCount = rawNodeCount.clamp(5, 50);
            final edgeCount = nodeCount - 1;

            // Ensure we have exactly edgeCount weights (pad with 100.0 if short,
            // or truncate if long — the generator bounds make padding rare).
            final weights = List<double>.generate(
              edgeCount,
              (i) => i < rawWeights.length ? rawWeights[i] : 100.0,
            );

            // Build locations and chain edges.
            final locations =
                List.generate(nodeCount, (i) => _makeLocation(i));
            final edges = _chainEdges(locations, weights);

            // Build the graph.
            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Pick distinct origin and destination indices.
            final originIdx = rawOriginIdx % nodeCount;
            var destIdx = rawDestIdx % nodeCount;
            if (destIdx == originIdx) {
              destIdx = (originIdx + 1) % nodeCount;
            }

            final originNode = service.graphNodes['loc-$originIdx']!;
            final destNode = service.graphNodes['loc-$destIdx']!;

            // Compute the route.
            final route = service.computeRoute(originNode, destNode);

            // A chain graph is always connected — a null route is a bug.
            expect(
              route,
              isNotNull,
              reason:
                  'computeRoute must return a route for a connected chain graph '
                  '(origin=loc-$originIdx, dest=loc-$destIdx)',
            );

            // Core assertion: totalDistanceMeters == sum of edge weights
            // along the route's node sequence.
            final edgeSum = _sumEdgesAlongRoute(service, route!.nodes);

            expect(
              route.totalDistanceMeters,
              closeTo(edgeSum, 1e-9),
              reason:
                  'route.totalDistanceMeters (${route.totalDistanceMeters}) '
                  'must equal the sum of adjacency-list weights along the '
                  'route path ($edgeSum)',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P1 edge-case: single-step route (adjacent nodes)
    //
    // When origin and destination are directly connected by one edge, the
    // route has exactly two nodes and totalDistanceMeters must equal that
    // edge's distanceMeters exactly.
    // -------------------------------------------------------------------------
    property(
      'P1 edge-case – single-step route totalDistanceMeters equals the direct edge weight',
      () {
        forAll(
          float(min: 1.0, max: 50000.0, nan: false, infinity: false),
          (edgeWeight) {
            // Two-node graph connected by one edge.
            final locations = [_makeLocation(0), _makeLocation(1)];
            final edges = _chainEdges(locations, [edgeWeight]);

            final service = RoutingService();
            service.buildGraph(locations, edges);

            final origin = service.graphNodes['loc-0']!;
            final destination = service.graphNodes['loc-1']!;

            final route = service.computeRoute(origin, destination);

            expect(
              route,
              isNotNull,
              reason: 'Route must exist for a two-node chain graph',
            );
            expect(
              route!.totalDistanceMeters,
              closeTo(edgeWeight, 1e-9),
              reason:
                  'Single-step route totalDistanceMeters (${route.totalDistanceMeters}) '
                  'must equal the direct edge weight ($edgeWeight)',
            );
            expect(
              route.nodes.length,
              equals(2),
              reason: 'Single-step route must contain exactly 2 nodes',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P1 edge-case: route from a node to itself
    //
    // computeRoute(origin, origin) — same start and end — should return a
    // route whose totalDistanceMeters is 0 and contains exactly one node.
    // -------------------------------------------------------------------------
    property(
      'P1 edge-case – same origin and destination yields zero-distance route',
      () {
        forAll(
          combine2(
            integer(min: 2, max: 20),
            list(
              float(min: 1.0, max: 5000.0, nan: false, infinity: false),
              minLength: 1,
              maxLength: 19,
            ),
          ),
          (data) {
            final (rawNodeCount, rawWeights) = data;
            final nodeCount = rawNodeCount.clamp(2, 20);
            final edgeCount = nodeCount - 1;
            final weights = List<double>.generate(
              edgeCount,
              (i) => i < rawWeights.length ? rawWeights[i] : 100.0,
            );

            final locations =
                List.generate(nodeCount, (i) => _makeLocation(i));
            final edges = _chainEdges(locations, weights);

            final service = RoutingService();
            service.buildGraph(locations, edges);

            // Use the first node as both origin and destination.
            final node = service.graphNodes['loc-0']!;
            final route = service.computeRoute(node, node);

            expect(
              route,
              isNotNull,
              reason:
                  'computeRoute(node, node) must return a non-null route',
            );
            expect(
              route!.totalDistanceMeters,
              closeTo(0.0, 1e-9),
              reason:
                  'Route from a node to itself must have totalDistanceMeters == 0, '
                  'got ${route.totalDistanceMeters}',
            );
            expect(
              route.nodes.length,
              equals(1),
              reason:
                  'Route from a node to itself must contain exactly 1 node',
            );
          },
          maxExamples: 100,
        );
      },
    );
  });
}
