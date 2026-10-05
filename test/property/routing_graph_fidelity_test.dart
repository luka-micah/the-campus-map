// Feature: campus-map-navigation, Property 10: Graph Construction Fidelity
//
// **Validates: Requirements 4.2, 4.3**
//
// For any set of valid LocationModel records and EdgeModel records, after
// calling RoutingService.buildGraph, every location record SHALL have a
// corresponding GraphNode with identical id, name, lat, and lng fields, and
// every well-formed edge record SHALL produce an adjacency-list entry with a
// weight equal to that edge's distanceMeters.

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: build a LocationModel from deterministic parts derived from an
  // integer index.  Using index-based IDs guarantees distinct IDs even when
  // the underlying string generator happens to produce duplicates.
  // ---------------------------------------------------------------------------
  LocationModel makeLocation(int index, String name, double lat, double lng) {
    return LocationModel(
      id: 'loc-$index',
      name: name.isEmpty ? 'Location $index' : name,
      department: 'Dept $index',
      lat: lat,
      lng: lng,
      hours: '08:00–17:00',
      createdAt: DateTime(2024, 1, 1),
    );
  }

  // ---------------------------------------------------------------------------
  // Property 10a – GraphNode fidelity
  //
  // For every LocationModel in the generated set, graphNodes[loc.id] must
  // exist and have id / name / lat / lng equal to the LocationModel values.
  // ---------------------------------------------------------------------------
  group('Property 10: Graph Construction Fidelity', () {
    property(
      'P10a – every location becomes a GraphNode with identical fields',
      () {
        // Generate a list of 1–20 locations using unique index-based IDs.
        forAll(
          // We use integer(min:1, max:20) for count, then combine with
          // individual field generators via list() + combine2.
          combine2(
            integer(min: 1, max: 20),
            list(
              combine3(
                string(minLength: 1, maxLength: 20),
                float(min: -90.0, max: 90.0, nan: false, infinity: false),
                float(min: -180.0, max: 180.0, nan: false, infinity: false),
              ),
              minLength: 1,
              maxLength: 20,
            ),
          ),
          (data) {
            final (count, triples) = data;

            // Build locations with distinct IDs (index-based).
            final effectiveCount = count.clamp(1, triples.length);
            final locations = <LocationModel>[];
            for (var i = 0; i < effectiveCount; i++) {
              final (name, lat, lng) = triples[i];
              locations.add(makeLocation(i, name, lat, lng));
            }

            final service = RoutingService();
            service.buildGraph(locations, []);

            final nodes = service.graphNodes;

            // Every location must have a matching GraphNode.
            for (final loc in locations) {
              expect(
                nodes.containsKey(loc.id),
                isTrue,
                reason: 'graphNodes should contain an entry for id=${loc.id}',
              );
              final node = nodes[loc.id]!;
              expect(node.id, equals(loc.id),
                  reason: 'GraphNode.id must equal LocationModel.id');
              expect(node.name, equals(loc.name),
                  reason: 'GraphNode.name must equal LocationModel.name');
              expect(node.lat, equals(loc.lat),
                  reason: 'GraphNode.lat must equal LocationModel.lat');
              expect(node.lng, equals(loc.lng),
                  reason: 'GraphNode.lng must equal LocationModel.lng');
            }

            // No extra nodes should be present.
            expect(
              nodes.length,
              equals(locations.length),
              reason: 'graphNodes.length must equal locations.length',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // Property 10b – adjacency-list edge weight fidelity
    //
    // For every well-formed EdgeModel (both endpoint IDs present in locations),
    // the adjacency list must contain bidirectional entries whose weight equals
    // the edge's distanceMeters.
    // -------------------------------------------------------------------------
    property(
      'P10b – every well-formed edge produces adjacency entries with correct weight',
      () {
        forAll(
          combine2(
            // Number of locations: 2–10 (need at least 2 to form edges).
            integer(min: 2, max: 10),
            // Number of edges: 1–15, each referencing random location indices.
            list(
              combine3(
                integer(min: 0, max: 9), // fromIndex (clamped to locationCount)
                integer(min: 0, max: 9), // toIndex   (clamped to locationCount)
                float(
                  min: 1.0,
                  max: 10000.0,
                  nan: false,
                  infinity: false,
                ),
              ),
              minLength: 1,
              maxLength: 15,
            ),
          ),
          (data) {
            final (locationCount, edgeTriples) = data;

            // Build distinct locations.
            final locations = List.generate(
              locationCount,
              (i) => makeLocation(
                i,
                'Node $i',
                (i * 0.001),   // distinct lat values
                (i * 0.001),   // distinct lng values
              ),
            );

            // Build well-formed edges (skip self-loops so fromId != toId).
            // Deduplicate edge pairs to avoid parallel edges between
            // the same two nodes (which makes firstWhere ambiguous).
            final edges = <EdgeModel>[];
            var edgeIndex = 0;
            final seenPairs = <Set<String>>{};
            for (final (fromIdx, toIdx, dist) in edgeTriples) {
              var from = fromIdx.clamp(0, locationCount - 1);
              var to = toIdx.clamp(0, locationCount - 1);
              // Make sure from != to so the edge is meaningful.
              if (from == to) {
                to = (to + 1) % locationCount;
              }
              final pairKey = from < to ? {from.toString(), to.toString()} : {to.toString(), from.toString()};
              if (seenPairs.contains(pairKey)) continue;
              seenPairs.add(pairKey);
              edges.add(EdgeModel(
                id: 'edge-$edgeIndex',
                fromLocationId: locations[from].id,
                toLocationId: locations[to].id,
                distanceMeters: dist,
              ));
              edgeIndex++;
              if (edges.length >= edgeTriples.length) break;
            }

            final service = RoutingService();
            service.buildGraph(locations, edges);

            final adj = service.adjacencyList;

            // Every well-formed edge must appear bidirectionally with the
            // correct weight.
            for (final edge in edges) {
              final fromId = edge.fromLocationId;
              final toId = edge.toLocationId;
              final weight = edge.distanceMeters;

              // Forward direction: fromId → toId
              final fromEdges = adj[fromId];
              expect(
                fromEdges,
                isNotNull,
                reason: 'adjacencyList should have entry for fromId=$fromId',
              );
              final forwardEntry = fromEdges!.where(
                (e) => e.targetNodeId == toId,
              );
              expect(
                forwardEntry.isNotEmpty,
                isTrue,
                reason:
                    'adjacencyList[$fromId] should contain entry targeting $toId',
              );
              expect(
                forwardEntry.any((e) => e.weight == weight),
                isTrue,
                reason:
                    'Forward edge weight should equal distanceMeters=$weight',
              );

              // Reverse direction: toId → fromId
              final toEdges = adj[toId];
              expect(
                toEdges,
                isNotNull,
                reason: 'adjacencyList should have entry for toId=$toId',
              );
              final reverseEntry = toEdges!.where(
                (e) => e.targetNodeId == fromId,
              );
              expect(
                reverseEntry.isNotEmpty,
                isTrue,
                reason:
                    'adjacencyList[$toId] should contain reverse entry targeting $fromId',
              );
              expect(
                reverseEntry.any((e) => e.weight == weight),
                isTrue,
                reason:
                    'Reverse edge weight should equal distanceMeters=$weight',
              );
            }
          },
          maxExamples: 100,
        );
      },
    );
  });
}
