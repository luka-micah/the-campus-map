# Implementation Plan: Campus Map Navigation

## Overview

Implements the BOUESTI Campus Map Flutter app in seven build phases that progressively layer functionality: project scaffold → graph/routing engine → Supabase/auth → map module → voice module → GPS/rerouting → admin CRUD. Each phase is independently testable, no orphaned code is left unwired, and all twelve correctness properties from the design are covered by property-based tests placed close to the corresponding implementation task.

## Tasks

- [x] 1. Scaffold project structure, data models, and core interfaces
  - Add required `pubspec.yaml` dependencies: `get`, `supabase_flutter`, `google_maps_flutter`, `geolocator`, `speech_to_text`, `flutter_tts`, `shared_preferences`, `collection`; dev deps: `test`, `fast_check`, `mocktail`
  - Create directory tree: `lib/core/`, `lib/features/auth/`, `lib/features/map/`, `lib/features/navigation/`, `lib/features/voice/`, `lib/features/admin/`, `lib/data/`, `lib/routing/`, `test/unit/`, `test/property/`, `test/integration/`
  - Define `LocationModel`, `GraphNode`, `EdgeModel`, `UserProfile`, `RouteModel`, and `_WeightedEdge` in `lib/core/models/`
  - Define `CampusRepository` abstract class with all method signatures in `lib/data/campus_repository.dart`
  - Define `AppRoutes` constants and `GetMaterialApp` shell with placeholder route map in `lib/main.dart`
  - _Requirements: 1.1, 2.1, 3.1, 4.1, 4.2, 4.3_

- [ ] 2. Implement graph construction and Dijkstra routing engine
  - [x] 2.1 Implement `RoutingService.buildGraph` — construct adjacency list from `LocationModel[]` and `EdgeModel[]`, skip malformed edges (missing node IDs) with a log, set `_rebuildPending` flag on update
    - File: `lib/routing/routing_service.dart`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [-] 2.2 Write property test for graph construction fidelity (Property 10)
    - **Property 10: Graph Construction Fidelity**
    - **Validates: Requirements 4.2, 4.3**
    - Generate random `LocationModel` + `EdgeModel` sets; assert every location has a corresponding `GraphNode` with identical `id`, `name`, `lat`, `lng`; assert every well-formed edge produces an adjacency entry with weight equal to `distanceMeters`
    - File: `test/property/routing_graph_fidelity_test.dart`
    - `// Feature: campus-map-navigation, Property 10: Graph Construction Fidelity`

  - [x] 2.3 Write property test for malformed-edge exclusion (Property 8)
    - **Property 8: Graph Malformed-Edge Exclusion**
    - **Validates: Requirements 4.4**
    - Inject edges referencing non-existent location IDs; assert `buildGraph` completes without exception, resulting graph contains only well-formed edges, and `computeRoute` still returns correct results for valid pairs
    - File: `test/property/routing_malformed_edge_test.dart`
    - `// Feature: campus-map-navigation, Property 8: Graph Malformed-Edge Exclusion`

  - [x] 2.4 Implement `RoutingService.nearestNode` — O(n) Haversine scan returning the `GraphNode` with minimum distance to a given `LatLng`
    - File: `lib/routing/routing_service.dart`
    - _Requirements: 5.2_

  - [x] 2.5 Write property test for nearest-node correctness (Property 4)
    - **Property 4: Nearest-Node Correctness**
    - **Validates: Requirements 5.2**
    - Generate random `LatLng` positions and node sets; assert the returned node's Haversine distance is ≤ every other node's distance
    - File: `test/property/routing_nearest_node_test.dart`
    - `// Feature: campus-map-navigation, Property 4: Nearest-Node Correctness`

  - [x] 2.6 Implement `RoutingService.computeRoute` — Dijkstra with `HeapPriorityQueue` (from `collection` package), early exit on reaching destination, path reconstruction into `RouteModel`
    - File: `lib/routing/routing_service.dart`
    - _Requirements: 5.3, 5.7, 5.8_

  - [-] 2.7 Write property test for route weight consistency (Property 1)
    - **Property 1: Route Weight Consistency**
    - **Validates: Requirements 5.7**
    - Generate random connected graphs (5–50 nodes); assert `route.totalDistanceMeters` equals the sum of `distanceMeters` for each consecutive edge in the route's node sequence; run 100 iterations
    - File: `test/property/routing_weight_consistency_test.dart`
    - `// Feature: campus-map-navigation, Property 1: Route Weight Consistency`

  - [-] 2.8 Write property test for route symmetry (Property 2)
    - **Property 2: Route Symmetry on Undirected Graphs**
    - **Validates: Requirements 5.8**
    - Generate random undirected graphs; assert `computeRoute(A,B).totalDistanceMeters == computeRoute(B,A).totalDistanceMeters` for all non-null route pairs; run 100 iterations
    - File: `test/property/routing_symmetry_test.dart`
    - `// Feature: campus-map-navigation, Property 2: Route Symmetry`

  - [-] 2.9 Write property test for Dijkstra optimality (Property 3)
    - **Property 3: Dijkstra Optimality**
    - **Validates: Requirements 5.3**
    - Generate small random graphs (3–10 nodes); compare Dijkstra result against brute-force path enumeration; assert Dijkstra distance ≤ every alternative path distance; run 100 iterations
    - File: `test/property/routing_optimality_test.dart`
    - `// Feature: campus-map-navigation, Property 3: Dijkstra Optimality`

  - [x] 2.10 Write unit tests for `RoutingService`
    - Test `buildGraph` with zero nodes, single node, disconnected graph
    - Test `computeRoute` returns `null` when no path exists
    - Test `nearestNode` with a single-node graph
    - File: `test/unit/routing_service_test.dart`

- [~] 3. Checkpoint — routing engine
  - Ensure all `test/property/` and `test/unit/routing_*` tests pass. Ask the user if any questions arise.

- [ ] 4. Implement Supabase backend integration and auth
  - [~] 4.1 Implement `SupabaseService` — initialise Supabase client from env constants, expose typed query helpers for `locations`, `edges`, and `profiles`
    - File: `lib/data/supabase_service.dart`
    - _Requirements: 1.2, 2.2_

  - [~] 4.2 Implement `SupabaseCampusRepository` (concrete implementation of `CampusRepository`) — `fetchLocations`, `fetchEdges`, `insertLocation`, `updateLocation`, `deleteLocation`, `insertEdge`, `deleteEdge`, `searchLocations`, `locationsStream`, `edgesStream`; write to `shared_preferences` on every successful fetch; fall back to cache on `PostgrestException`/timeout
    - File: `lib/data/supabase_campus_repository.dart`
    - _Requirements: 3.5, 3.6, 12.1, 12.2, 12.3, 14.1_

  - [~] 4.3 Write property test for location search case-insensitivity and partial match (Property 5)
    - **Property 5: Location Search Case-Insensitivity and Partial Match**
    - **Validates: Requirements 8.4**
    - Use an in-memory list of random location names; for any non-empty substring S drawn from a name (in any capitalisation), assert `searchLocations(S)` includes that location and excludes locations whose names do not contain S case-insensitively; run 100 iterations
    - File: `test/property/repository_search_test.dart`
    - `// Feature: campus-map-navigation, Property 5: Location Search Case-Insensitivity`

  - [~] 4.4 Write unit tests for `CampusRepository`
    - Test offline cache fallback: when `SupabaseService` throws, assert `fetchLocations` returns cached data and sets `isOfflineMode`
    - Test `locationsStream` emits on Realtime insert events using a mock Supabase channel
    - File: `test/unit/campus_repository_test.dart`

  - [~] 4.5 Implement `AuthService` — `register`, `login`, `logout`, `restoreSession` wrapping Supabase Auth; on register success, insert `profiles` row via `SupabaseService`
    - File: `lib/features/auth/auth_service.dart`
    - _Requirements: 1.2, 2.2, 2.4, 2.5_

  - [~] 4.6 Implement `AuthController` with `register`, `login`, `logout`, `restoreSession`; reactive state `currentUser`, `isLoading`, `errorMessage`; display inline error messages for duplicate username, duplicate email, short password, and invalid credentials
    - File: `lib/features/auth/auth_controller.dart`
    - _Requirements: 1.1, 1.3, 1.4, 1.5, 1.6, 2.1, 2.3, 2.4, 2.5_

  - [~] 4.7 Implement `AuthBinding`, `LoginView`, and `RegisterView` widgets; wire `AuthMiddleware` GetX middleware for route guards
    - Files: `lib/features/auth/auth_binding.dart`, `lib/features/auth/views/login_view.dart`, `lib/features/auth/views/register_view.dart`
    - _Requirements: 1.1, 2.1_

  - [~] 4.8 Write unit tests for `AuthController`
    - Test registration validation: password < 8 chars, duplicate email, duplicate username all show correct error messages
    - Test login with invalid credentials shows generic error without revealing which field is wrong
    - Test `restoreSession` navigates to map on valid session, stays on login on null session
    - File: `test/unit/auth_controller_test.dart`

- [~] 5. Checkpoint — auth and data layer
  - Ensure all auth and repository tests pass, app launches, and routing to login/map works. Ask the user if any questions arise.

- [ ] 6. Implement map module
  - [~] 6.1 Implement `LocationService` — wrap `geolocator` `getPositionStream(distanceFilter: 5, desiredAccuracy: LocationAccuracy.high)`; request foreground permission on first call; expose `hasSignal` boolean stream with 15-second timeout; notify controller when permission denied
    - File: `lib/features/map/location_service.dart`
    - _Requirements: 3.4, 13.1, 13.2, 13.4, 14.4_

  - [~] 6.2 Implement `MapController` — `fetchLocations`, `onMarkerTapped`, `subscribeToRealtimeUpdates`; reactive state `locations`, `userPosition`, `hasFetchError`, `isOfflineMode`; subscribe to `LocationService` stream; cancel subscription in `onClose`
    - File: `lib/features/map/map_controller.dart`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 13.2, 14.1, 14.2_

  - [~] 6.3 Write property test for marker placement completeness (Property 11)
    - **Property 11: Marker Placement Completeness**
    - **Validates: Requirements 3.2**
    - Generate random location sets of size 1–100; assert that after `MapController` processes them the resulting marker list has exactly N entries, each at the correct `lat`/`lng`, with no duplicates; run 100 iterations
    - File: `test/property/map_marker_completeness_test.dart`
    - `// Feature: campus-map-navigation, Property 11: Marker Placement Completeness`

  - [~] 6.4 Write unit tests for `MapController`
    - Test markers are placed correctly from a fixture location list
    - Test `hasFetchError` is set and retry option available when repository throws
    - Test `isOfflineMode` banner displayed when cached data is served
    - File: `test/unit/map_controller_test.dart`

  - [~] 6.5 Implement `MapBinding` and `MapView` — Google Maps widget centred on BOUESTI coordinates, marker tap → info panel, position indicator, offline/error banners, retry button, browse-only mode when GPS denied
    - Files: `lib/features/map/map_binding.dart`, `lib/features/map/views/map_view.dart`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 13.2, 13.3, 14.2, 14.3_

- [ ] 7. Implement voice module
  - [~] 7.1 Implement `VoiceService` — wrap `speech_to_text` `listen()` with a 10-second timeout; auto-call `stopListening()` on timeout or no speech; wrap `flutter_tts` with `speak`, `stop`; expose `onComplete` callback
    - File: `lib/features/voice/voice_service.dart`
    - _Requirements: 8.1, 8.2, 8.8, 9.1, 9.2_

  - [~] 7.2 Implement `VoiceController` — reactive state `isMuted`, `isListening`, `ttsQueue`; `startListening`, `stopListening`, `speak` (enqueue + play), `mute` (clear queue + stop TTS), `unmute` (resume from current step); on STT result pass text to `CampusRepository.searchLocations`; handle 0/1/many match results per design STT flow
    - File: `lib/features/voice/voice_controller.dart`
    - _Requirements: 8.1, 8.3, 8.4, 8.5, 8.6, 8.7, 9.1, 9.2, 9.3, 9.5, 9.6_

  - [~] 7.3 Write property test for TTS queue ordering (Property 6)
    - **Property 6: TTS Queue Ordering**
    - **Validates: Requirements 9.2**
    - Simulate random sequences of 1–20 `speak(text)` calls while TTS is "busy"; capture the order utterances are delivered to `flutter_tts`; assert FIFO ordering with no skips or reorderings; run 100 iterations
    - File: `test/property/voice_queue_ordering_test.dart`
    - `// Feature: campus-map-navigation, Property 6: TTS Queue Ordering`

  - [~] 7.4 Write unit tests for `VoiceController`
    - Test `mute` stops ongoing utterance and clears queue
    - Test `unmute` resumes TTS from current navigation step
    - Test STT timeout produces empty string and TTS "no location found" response
    - Test 0 / 1 / multiple match outcomes each trigger the correct downstream action
    - File: `test/unit/voice_controller_test.dart`

  - [~] 7.5 Implement `VoiceBinding` and voice UI widgets — mic FAB, match list bottom sheet, mute/unmute toggle, permission dialog
    - Files: `lib/features/voice/voice_binding.dart`, `lib/features/voice/widgets/`
    - _Requirements: 8.1, 8.5, 8.7, 8.8_

- [~] 8. Checkpoint — map and voice modules
  - Ensure all map, voice, property and unit tests pass. Ask the user if any questions arise.

- [ ] 9. Implement navigation module with GPS tracking and rerouting
  - [~] 9.1 Implement `NavigationController` — reactive state `activeRoute`, `currentStepIndex`, `remainingDistance`, `isNavigating`, `isRerouting`; methods `startNavigation`, `onPositionUpdate`, `triggerReroute`, `cancelNavigation`, `_hasDeviated`; subscribe to `LocationService` stream; cancel in `onClose`; GetX `ever` workers for step-advance and deviation check
    - File: `lib/features/navigation/navigation_controller.dart`
    - _Requirements: 5.1, 5.2, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5, 7.1, 7.2, 7.3, 7.4, 7.5, 14.4_

  - [~] 9.2 Write property test for deviation detection threshold (Property 12)
    - **Property 12: Deviation Detection Threshold**
    - **Validates: Requirements 7.2**
    - Generate random GPS positions and polylines; assert `_hasDeviated(P, polyline)` is `true` iff the minimum perpendicular Haversine distance from P to any polyline segment exceeds 30 metres; run 100 iterations
    - File: `test/property/navigation_deviation_test.dart`
    - `// Feature: campus-map-navigation, Property 12: Deviation Detection Threshold`

  - [~] 9.3 Write unit tests for `NavigationController`
    - Test step auto-advances when user passes a waypoint
    - Test arrival detected within 15 m radius of destination node
    - Test `cancelNavigation` clears route, stops GPS callbacks, navigates to map screen
    - Test reroute failure retains previous route and shows error
    - Test GPS signal loss pauses deviation checks and shows banner
    - File: `test/unit/navigation_controller_test.dart`

  - [~] 9.4 Implement `NavigationBinding` and `NavigationView` — polyline overlay, current instruction banner, remaining distance label, arrival confirmation dialog, GPS-lost banner, rerouting spinner
    - Files: `lib/features/navigation/navigation_binding.dart`, `lib/features/navigation/views/navigation_view.dart`
    - _Requirements: 5.5, 6.1, 6.3, 6.4, 6.5, 7.4, 14.4_

  - [~] 9.5 Wire `NavigationController` ↔ `VoiceController` — GetX `ever` worker on `currentStepIndex` speaks the new `turnInstruction` via `VoiceController.speak`; reroute event speaks notification before first new instruction
    - File: `lib/features/navigation/navigation_controller.dart`
    - _Requirements: 9.1, 9.3, 9.4_

- [~] 10. Checkpoint — navigation module
  - Ensure all navigation, deviation, and wiring tests pass. Ask the user if any questions arise.

- [ ] 11. Implement admin CRUD module
  - [~] 11.1 Implement `AdminController` — `createLocation`, `updateLocation`, `deleteLocation` (atomic: deletes edges first then location, rolls back on failure), `createEdge`, `deleteEdge`; input validation: name not empty/whitespace, lat/lng present, distanceMeters > 0, fromId ≠ toId, both location IDs exist
    - File: `lib/features/admin/admin_controller.dart`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 11.1, 11.2, 11.3, 11.4, 11.5_

  - [~] 11.2 Write property test for admin form validation (Property 7)
    - **Property 7: Admin Form Validation Rejects Invalid Inputs**
    - **Validates: Requirements 10.7, 11.4**
    - Generate random whitespace-only/empty `name` strings and random `distanceMeters ≤ 0` values; assert `AdminController` rejects them without calling `CampusRepository` and the local locations/edges list is unchanged; run 100 iterations
    - File: `test/property/admin_validation_test.dart`
    - `// Feature: campus-map-navigation, Property 7: Admin Form Validation Rejects Invalid Inputs`

  - [~] 11.3 Write property test for RLS non-admin write rejection (Property 9)
    - **Property 9: RLS Write Rejection for Non-Admins**
    - **Validates: Requirements 10.6**
    - Using a Supabase test project (or a local mock that mirrors RLS): generate random non-admin credentials and random INSERT/UPDATE/DELETE operations on `locations` and `edges`; assert every attempt returns a permission error and table data is unchanged; run 100 iterations
    - File: `test/property/rls_non_admin_test.dart`
    - `// Feature: campus-map-navigation, Property 9: RLS Non-Admin Write Rejection`

  - [~] 11.4 Write unit tests for `AdminController`
    - Test atomic delete rolls back location deletion when edge deletion fails (mock repository throws on `deleteEdge`)
    - Test self-loop edge (`fromId == toId`) is rejected with validation error
    - Test create/update/delete for locations propagate through repository mock correctly
    - File: `test/unit/admin_controller_test.dart`

  - [~] 11.5 Implement `AdminBinding` and `AdminDashboardView` — location list, create/edit location form, delete confirmation dialog, edge list, create/delete edge form; admin nav entry visible only to admin users
    - Files: `lib/features/admin/admin_binding.dart`, `lib/features/admin/views/admin_dashboard_view.dart`, `lib/features/admin/views/location_form_view.dart`, `lib/features/admin/views/edge_form_view.dart`
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.7, 11.1, 11.4, 11.5_

- [~] 12. Checkpoint — admin module
  - Ensure all admin tests pass and CRUD flows update the live map via Realtime. Ask the user if any questions arise.

- [ ] 13. Integration wiring — wire all modules together and write integration tests
  - [~] 13.1 Wire startup sequence in `main.dart` — `SupabaseService.initialise`, `AuthController.restoreSession`, conditional navigation to `MapView` or `LoginView`, `CampusRepository.fetchLocations + fetchEdges`, `RoutingService.buildGraph`
    - File: `lib/main.dart`
    - _Requirements: 2.4, 3.1, 4.1_

  - [~] 13.2 Wire Realtime subscriptions — `MapController.subscribeToRealtimeUpdates` calls `CampusRepository.locationsStream`; `RoutingService` listens on `CampusRepository.edgesStream` and rebuilds graph; Admin changes propagate to live map without restart
    - Files: `lib/features/map/map_controller.dart`, `lib/routing/routing_service.dart`
    - _Requirements: 3.6, 4.5, 12.1, 12.2, 12.3_

  - [~] 13.3 Write integration test: login → map loads with markers
    - Authenticate with a test Supabase project (or stub); assert `MapController.locations` is non-empty and markers render on the map widget
    - File: `test/integration/login_map_integration_test.dart`

  - [~] 13.4 Write integration test: admin creates location → Realtime → map updates
    - Admin controller inserts a location; assert `locationsStream` emits and `MapController.locations` grows by one
    - File: `test/integration/admin_realtime_integration_test.dart`

  - [~] 13.5 Write integration test: voice STT → route computed → TTS speaks first instruction
    - Mock STT returning a known location name; assert `NavigationController` starts navigation and `VoiceController.speak` is called with the first turn instruction
    - File: `test/integration/voice_navigation_integration_test.dart`

- [~] 14. Final checkpoint — full suite
  - Ensure all unit, property, and integration tests pass. Run `flutter analyze` and fix any lint/type issues. Ask the user if any questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP build; all property-based tests run a minimum of 100 iterations as specified in the design.
- The design uses Dart/Flutter throughout — all code examples use Dart idioms and the packages listed in the scaffold task.
- Each property test file MUST include the comment `// Feature: campus-map-navigation, Property N: <property text>` at the top of the test.
- The `fast_check` package is used for all property-based tests; `mocktail` is used for all service mocks.
- RLS property test (P9) requires either a Supabase test project or a sufficiently faithful Supabase mock — mark as integration-level if a live project is unavailable.
- Tasks that read/write the same file (e.g., `routing_service.dart`) are placed in separate waves in the dependency graph.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["2.1", "2.4"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.5"] },
    { "id": 3, "tasks": ["2.6"] },
    { "id": 4, "tasks": ["2.7", "2.8", "2.9", "2.10"] },
    { "id": 5, "tasks": ["4.1"] },
    { "id": 6, "tasks": ["4.2", "4.5"] },
    { "id": 7, "tasks": ["4.3", "4.4", "4.6"] },
    { "id": 8, "tasks": ["4.7", "4.8"] },
    { "id": 9, "tasks": ["6.1", "6.2"] },
    { "id": 10, "tasks": ["6.3", "6.4"] },
    { "id": 11, "tasks": ["6.5", "7.1"] },
    { "id": 12, "tasks": ["7.2", "7.3", "7.4"] },
    { "id": 13, "tasks": ["7.5", "9.1"] },
    { "id": 14, "tasks": ["9.2", "9.3"] },
    { "id": 15, "tasks": ["9.4", "9.5"] },
    { "id": 16, "tasks": ["11.1"] },
    { "id": 17, "tasks": ["11.2", "11.3", "11.4"] },
    { "id": 18, "tasks": ["11.5"] },
    { "id": 19, "tasks": ["13.1", "13.2"] },
    { "id": 20, "tasks": ["13.3", "13.4", "13.5"] }
  ]
}
```
