// Feature: campus-map-navigation, Property 4: Nearest-Node Correctness
//
// **Validates: Requirements 5.2**
//
// For any GPS position P and campus graph with N nodes, the node returned by
// RoutingService.nearestNode(P) SHALL have a Haversine distance to P that is
// less than or equal to the Haversine distance from P to every other node in
// the graph.

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/routing/routing_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helper: create a LocationModel from an index and coordinate pair so every
  // node gets a unique ID regardless of what the generators produce.
  // ---------------------------------------------------------------------------
  LocationModel makeLocation(int index, double lat, double lng) {
    return LocationModel(
      id: 'node-$index',
      name: 'Node $index',
      department: '',
      lat: lat,
      lng: lng,
      hours: '',
      createdAt: DateTime(2024, 1, 1),
    );
  }

  // ---------------------------------------------------------------------------
  // Property 4: Nearest-Node Correctness
  //
  // Given:
  //   • a non-empty set of GraphNodes built from random LocationModels
  //   • a random query LatLng
  // When:
  //   • RoutingService.nearestNode(queryPosition) is called
  // Then:
  //   • the returned node's Haversine distance to queryPosition is ≤ the
  //     Haversine distance from queryPosition to every other node in the graph.
  // ---------------------------------------------------------------------------
  group('Property 4: Nearest-Node Correctness', () {
    property(
      'P4 – nearestNode returns the node with minimum Haversine distance',
      () {
        forAll(
          combine3(
            // Query position: random lat/lng anywhere on Earth.
            float(min: -90.0, max: 90.0, nan: false, infinity: false),
            float(min: -180.0, max: 180.0, nan: false, infinity: false),
            // Node set: 1–30 nodes, each with a random lat/lng.
            list(
              combine2(
                float(min: -90.0, max: 90.0, nan: false, infinity: false),
                float(min: -180.0, max: 180.0, nan: false, infinity: false),
              ),
              minLength: 1,
              maxLength: 30,
            ),
          ),
          (data) {
            final (queryLat, queryLng, nodeCoords) = data;

            // Build locations with unique index-based IDs.
            final locations = <LocationModel>[];
            for (var i = 0; i < nodeCoords.length; i++) {
              final (lat, lng) = nodeCoords[i];
              locations.add(makeLocation(i, lat, lng));
            }

            final service = RoutingService();
            service.buildGraph(locations, []);

            final queryPosition = LatLng(queryLat, queryLng);
            final result = service.nearestNode(queryPosition);

            // Distance from the query position to the returned node.
            final resultDistance = RoutingService.haversineMeters(
              queryLat,
              queryLng,
              result.lat,
              result.lng,
            );

            // Assert: every other node is at least as far away.
            for (final loc in locations) {
              if (loc.id == result.id) continue;

              final candidateDistance = RoutingService.haversineMeters(
                queryLat,
                queryLng,
                loc.lat,
                loc.lng,
              );

              expect(
                resultDistance,
                lessThanOrEqualTo(candidateDistance),
                reason:
                    'nearestNode returned node "${result.id}" '
                    '(distance=${resultDistance.toStringAsFixed(2)} m) '
                    'but node "${loc.id}" '
                    '(distance=${candidateDistance.toStringAsFixed(2)} m) '
                    'is closer to the query position '
                    'LatLng($queryLat, $queryLng)',
              );
            }
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // Edge-case: single-node graph — nearestNode must return that sole node.
    // -------------------------------------------------------------------------
    property(
      'P4 edge-case – single-node graph always returns the only node',
      () {
        forAll(
          combine4(
            float(min: -90.0, max: 90.0, nan: false, infinity: false),
            float(min: -180.0, max: 180.0, nan: false, infinity: false),
            float(min: -90.0, max: 90.0, nan: false, infinity: false),
            float(min: -180.0, max: 180.0, nan: false, infinity: false),
          ),
          (data) {
            final (queryLat, queryLng, nodeLat, nodeLng) = data;

            final locations = [makeLocation(0, nodeLat, nodeLng)];

            final service = RoutingService();
            service.buildGraph(locations, []);

            final queryPosition = LatLng(queryLat, queryLng);
            final result = service.nearestNode(queryPosition);

            expect(
              result.id,
              equals('node-0'),
              reason:
                  'Single-node graph must return the only available node',
            );
          },
          maxExamples: 100,
        );
      },
    );

    // -------------------------------------------------------------------------
    // Edge-case: a position identical to a node's coordinates must return that
    // node (distance 0 is the global minimum).
    // -------------------------------------------------------------------------
    property(
      'P4 edge-case – query at a node\'s exact coordinates returns that node',
      () {
        forAll(
          combine2(
            // Generate a list of 1–20 nodes.
            list(
              combine2(
                float(min: -90.0, max: 90.0, nan: false, infinity: false),
                float(min: -180.0, max: 180.0, nan: false, infinity: false),
              ),
              minLength: 1,
              maxLength: 20,
            ),
            // Pick one node index to use as the query position.
            integer(min: 0, max: 19),
          ),
          (data) {
            final (nodeCoords, rawPickIndex) = data;
            final pickIndex = rawPickIndex % nodeCoords.length;

            final locations = <LocationModel>[];
            for (var i = 0; i < nodeCoords.length; i++) {
              final (lat, lng) = nodeCoords[i];
              locations.add(makeLocation(i, lat, lng));
            }

            final service = RoutingService();
            service.buildGraph(locations, []);

            // Query at the exact coordinates of the chosen node.
            final chosenLocation = locations[pickIndex];
            final queryPosition =
                LatLng(chosenLocation.lat, chosenLocation.lng);
            final result = service.nearestNode(queryPosition);

            // The returned node must be at least as close as every other node.
            // (Multiple nodes could share identical coordinates, so we check
            // distance rather than ID equality.)
            final resultDistance = RoutingService.haversineMeters(
              chosenLocation.lat,
              chosenLocation.lng,
              result.lat,
              result.lng,
            );

            expect(
              resultDistance,
              closeTo(0.0, 1e-6),
              reason:
                  'Query at exact node coordinates should return a node with '
                  'distance ≈ 0 m, got $resultDistance m for node "${result.id}"',
            );
          },
          maxExamples: 100,
        );
      },
    );
  });
}
