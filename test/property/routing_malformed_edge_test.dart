// Feature: campus-map-navigation, Property 8: Graph Malformed-Edge Exclusion
//
// **Validates: Requirements 4.4**
//
// For any set of location records and edge records where one or more edges
// reference non-existent location IDs, RoutingService.buildGraph SHALL:
//   a) complete without throwing an exception,
//   b) produce an adjacency list that contains ONLY edges whose both endpoint
//      IDs are present in the provided location records, and
//   c) still return correct route results for all well-formed node pairs
//      (tested once computeRoute is fully implemented).

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a deterministic [LocationModel] from an integer index.
/// Index-based IDs guarantee uniqueness across the generated set.
LocationModel _makeLocation(int index) {
  return LocationModel(
    id: 'loc-$index',
    name: 'Location $index',
    department: 'Dept $index',
    // Spread out slightly so Haversine distances are distinct.
    lat: 7.0 + index * 0.001,
    lng: 5.0 + index * 0.001,
    hours: '08:00–17:00',
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Creates a well-formed [EdgeModel] between two valid location indices.
EdgeModel _makeValidEdge(
  int edgeIndex,
  List<LocationModel> locations,
  int fromIdx,
  int toIdx,
  double distance,
) {
  return EdgeModel(
    id: 'edge-valid-$edgeIndex',
    fromLocationId: locations[fromIdx].id,
    toLocationId: locations[toIdx].id,
    distanceMeters: distance,
  );
}

/// Creates a malformed [EdgeModel] that references an ID not present in
/// [locations]. The bogus ID is guaranteed to be outside the valid set by
/// prefixing with `'ghost-'`.
EdgeModel _makeMalformedEdge(int edgeIndex, String bogusId) {
  return EdgeModel(
    id: 'edge-malformed-$edgeIndex',
    fromLocationId: bogusId,
    toLocationId: bogusId,
    distanceMeters: 100.0,
  );
}

/// Returns `true` when every entry in [adjacencyList] references only IDs that
/// appear in [validIds].
bool _adjacencyListContainsOnlyValidIds(
  Map<String, List<dynamic>> adjacencyList,
  Set<String> validIds,
) {
  for (final entry in adjacencyList.entries) {
    // The outer key must be a valid node ID.
    if (!validIds.contains(entry.key)) return false;
    // Each WeightedEdge target must also be a valid node ID.
    for (final we in entry.value) {
      // WeightedEdge exposes targetNodeId.
      if (!validIds.contains(we.targetNodeId as String)) return false;
    }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Property 8: Graph Malformed-Edge Exclusion', () {
    // -------------------------------------------------------------------------
    // P8a — buildGraph completes without exception when malformed edges are
    //        present.
    // -------------------------------------------------------------------------
    property(
      'P8a – buildGraph does not throw when edges reference non-existent IDs',
      () {
        forAll(
          combine2(
            // 2–10 valid locations.
            integer(min: 2, max: 10),
            // 1–5 malformed edges (ghost IDs).
            integer(min: 1, max: 5),
          ),
          (data) {
            final (locationCount, malformedCount) = data;

            final locations =
                List.generate(locationCount, _makeLocation);

            // Build a set of malformed edges with IDs that do not exist.
            final malformedEdges = List.generate(
              malformedCount,
              (i) => _makeMalformedEdge(i, 'ghost-${i + locationCount * 100}'),
            );

            final service = RoutingService();

            // This must not throw — the core assertion for P8a.
            expect(
              () => service.buildGraph(locations, malformedEdges),
              returnsNormally,
              reason:
                  'buildGraph must complete without exception even when '
                  'all supplied edges are malformed.',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P8b — The resulting adjacency list contains ONLY well-formed edges.
    //        Malformed edges must be silently excluded.
    // -------------------------------------------------------------------------
    property(
      'P8b – adjacency list contains only edges with valid endpoint IDs',
      () {
        forAll(
          combine3(
            // 2–10 valid locations.
            integer(min: 2, max: 10),
            // 1–10 well-formed edges (indices into the location list).
            list(
              combine3(
                integer(min: 0, max: 9), // fromIndex (clamped later)
                integer(min: 0, max: 9), // toIndex   (clamped later)
                float(
                  min: 1.0,
                  max: 5000.0,
                  nan: false,
                  infinity: false,
                ),
              ),
              minLength: 1,
              maxLength: 10,
            ),
            // 1–5 malformed edges (ghost IDs).
            integer(min: 1, max: 5),
          ),
          (data) {
            final (locationCount, edgeTriples, malformedCount) = data;

            final locations =
                List.generate(locationCount, _makeLocation);
            final validIds = {for (final l in locations) l.id};

            // Build valid edges (skip self-loops for meaningfulness).
            final validEdges = <EdgeModel>[];
            for (var i = 0; i < edgeTriples.length; i++) {
              final (fromRaw, toRaw, dist) = edgeTriples[i];
              final from = fromRaw.clamp(0, locationCount - 1);
              var to = toRaw.clamp(0, locationCount - 1);
              if (from == to) to = (to + 1) % locationCount;
              validEdges.add(
                _makeValidEdge(i, locations, from, to, dist),
              );
            }

            // Build malformed edges.
            final malformedEdges = List.generate(
              malformedCount,
              (i) => _makeMalformedEdge(
                i,
                'ghost-${i + locationCount * 100}',
              ),
            );

            final allEdges = [...validEdges, ...malformedEdges];

            final service = RoutingService();
            service.buildGraph(locations, allEdges);

            final adj = service.adjacencyList;

            // --- assertion 1: all outer keys are valid node IDs ---
            for (final key in adj.keys) {
              expect(
                validIds.contains(key),
                isTrue,
                reason:
                    'adjacencyList key "$key" is not a valid location ID.',
              );
            }

            // --- assertion 2: all WeightedEdge targets are valid node IDs ---
            for (final entries in adj.values) {
              for (final we in entries) {
                expect(
                  validIds.contains(we.targetNodeId),
                  isTrue,
                  reason:
                      'adjacencyList contains entry targeting '
                      '"${we.targetNodeId}" which is not a valid location ID.',
                );
              }
            }

            // --- assertion 3: every valid edge appears (both directions) ---
            for (final edge in validEdges) {
              final fromEdges = adj[edge.fromLocationId];
              expect(
                fromEdges,
                isNotNull,
                reason:
                    'No adjacency entry for fromLocationId='
                    '${edge.fromLocationId}',
              );
              expect(
                fromEdges!.any(
                  (we) => we.targetNodeId == edge.toLocationId,
                ),
                isTrue,
                reason:
                    'Well-formed edge ${edge.id} not found in forward direction.',
              );

              final toEdges = adj[edge.toLocationId];
              expect(
                toEdges,
                isNotNull,
                reason:
                    'No adjacency entry for toLocationId='
                    '${edge.toLocationId}',
              );
              expect(
                toEdges!.any(
                  (we) => we.targetNodeId == edge.fromLocationId,
                ),
                isTrue,
                reason:
                    'Well-formed edge ${edge.id} not found in reverse direction.',
              );
            }

            // --- assertion 4: total adjacency entries count matches valid
            //     edges only (each valid edge contributes 2 entries: fwd + rev,
            //     duplicates between parallel edges are counted separately) ---
            final totalEntries =
                adj.values.fold<int>(0, (sum, list) => sum + list.length);
            // Each valid edge → 2 WeightedEdge entries (undirected).
            // Malformed edges → 0 entries.
            expect(
              totalEntries,
              equals(validEdges.length * 2),
              reason:
                  'Total adjacency entries should be ${validEdges.length * 2} '
                  '(2 per valid edge); malformed edges must not contribute.',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // P8c — Mixed scenario: only malformed edges present → empty adjacency,
    //        graph nodes still contain all locations.
    // -------------------------------------------------------------------------
    property(
      'P8c – with only malformed edges, graph nodes are populated but '
      'adjacency list is empty of connections',
      () {
        forAll(
          combine2(
            integer(min: 1, max: 15),  // location count
            integer(min: 1, max: 10),  // malformed edge count
          ),
          (data) {
            final (locationCount, malformedCount) = data;

            final locations =
                List.generate(locationCount, _makeLocation);

            final malformedEdges = List.generate(
              malformedCount,
              (i) => _makeMalformedEdge(
                i,
                'ghost-${i + locationCount * 100}',
              ),
            );

            final service = RoutingService();

            // Must not throw.
            expect(
              () => service.buildGraph(locations, malformedEdges),
              returnsNormally,
            );

            // All locations are present as graph nodes.
            final nodes = service.graphNodes;
            expect(
              nodes.length,
              equals(locationCount),
              reason: 'All locations must become graph nodes.',
            );
            for (final loc in locations) {
              expect(
                nodes.containsKey(loc.id),
                isTrue,
                reason: 'GraphNode missing for id=${loc.id}.',
              );
            }

            // Adjacency list has entries for every node but all lists are empty
            // (no well-formed edges to add).
            final adj = service.adjacencyList;
            for (final loc in locations) {
              final edges = adj[loc.id];
              expect(
                edges,
                isNotNull,
                reason:
                    'adjacencyList must have an (empty) entry for every '
                    'node id=${loc.id}.',
              );
              expect(
                edges!,
                isEmpty,
                reason:
                    'adjacencyList[${loc.id}] should be empty because all '
                    'supplied edges are malformed.',
              );
            }
          },
          maxExamples: 100,
        );
      },
    );
  });
}
