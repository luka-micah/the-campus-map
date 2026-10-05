# Requirements Document

## Introduction

The Campus Map is a cross-platform Flutter mobile application (Android-first, iOS-compatible) designed to provide campus navigation at Bamidele Olumilua University of Education, Science and Technology (BOUESTI). The app enables students, staff, and visitors to locate campus buildings, compute optimal walking routes using a custom Dijkstra graph algorithm, and follow spoken turn-by-turn directions hands-free via an integrated voice assistant. A secured admin panel allows authorised staff to manage the campus location database without requiring app code changes.

## Glossary

- **App**: The Campus Map Flutter mobile application.
- **User**: Any authenticated person using the App (student, staff, or visitor).
- **Admin**: A User whose `is_admin` flag on the `profiles` table is `true`.
- **Auth_Controller**: The GetX controller managing authentication state, wrapping Supabase Auth.
- **Map_Controller**: The GetX controller managing the Google Maps view and campus marker state.
- **Navigation_Controller**: The GetX controller managing active route state, step progression, and rerouting logic.
- **Voice_Controller**: The GetX controller exposing speech-to-text and text-to-speech functionality to other modules.
- **Admin_Controller**: The GetX controller managing CRUD operations for campus locations, gated by admin privileges.
- **Campus_Repository**: The data-access layer that mediates between Supabase services and controllers.
- **Routing_Service**: The service that builds the campus graph from `locations` and `edges` tables and implements Dijkstra's shortest-path algorithm.
- **Voice_Service**: The service wrapping `speech_to_text` (STT) and `flutter_tts` (TTS) packages.
- **Location_Service**: The service wrapping `geolocator` for live GPS position tracking.
- **Auth_Service**: The service wrapping Supabase Auth for email/username and password operations.
- **Supabase_Service**: The base Supabase client and shared query helpers.
- **Graph_Node**: A data model representing a campus location or path junction, used as a vertex in the routing graph.
- **Location**: A named campus point of interest stored in the `locations` Supabase table (`id`, `name`, `department`, `lat`, `lng`, `hours`, `created_at`).
- **Edge**: A directed or undirected walkable path between two Graph_Nodes stored in the `edges` Supabase table (`id`, `from_location_id`, `to_location_id`, `distance_meters`).
- **Route**: The ordered list of Graph_Nodes returned by the Routing_Service representing the shortest walking path from an origin to a destination.
- **Turn_Instruction**: A human-readable, spoken direction string generated for each step of a Route.
- **Deviation**: A condition detected when the User's live GPS position diverges from the active Route by more than a configurable threshold.
- **RLS**: Supabase Row Level Security policies enforcing data access rules at the database layer.
- **Profile**: A row in the `profiles` Supabase table (`id` UUID FK to `auth.users`, `username`, `is_admin`).
- **STT**: Speech-to-text — converting the User's spoken words into a text destination query.
- **TTS**: Text-to-speech — converting Turn_Instruction strings into spoken audio output.

---

## Requirements

### Requirement 1: User Registration

**User Story:** As a new User, I want to create an account with a username and password, so that I can access the App's navigation features securely.

#### Acceptance Criteria

1. THE Auth_Controller SHALL provide a registration form that accepts a username, email address, and password.
2. WHEN a User submits valid registration credentials, THE Auth_Service SHALL create a new Supabase Auth user and a corresponding Profile row with `is_admin` set to `false`.
3. IF a submitted username already exists in the `profiles` table, THEN THE Auth_Controller SHALL display an error message stating the username is already taken.
4. IF a submitted email address is already registered, THEN THE Auth_Controller SHALL display an error message stating the email is already in use.
5. IF a submitted password is fewer than 8 characters, THEN THE Auth_Controller SHALL display an error message stating the password minimum length requirement.
6. WHEN registration succeeds, THE Auth_Controller SHALL navigate the User to the Campus Map screen.

---

### Requirement 2: User Login

**User Story:** As a registered User, I want to log in with my credentials, so that I can access the App from any device.

#### Acceptance Criteria

1. THE Auth_Controller SHALL provide a login form that accepts an email address and password.
2. WHEN a User submits valid login credentials, THE Auth_Service SHALL authenticate the User via Supabase Auth and restore the User's session.
3. IF submitted credentials are invalid, THEN THE Auth_Controller SHALL display an error message stating the credentials are incorrect without revealing which field is wrong.
4. WHEN the App is launched and an active Supabase Auth session exists, THE Auth_Service SHALL validate and refresh the session with Supabase and, WHEN validation succeeds, THE Auth_Controller SHALL navigate directly to the Campus Map screen without showing the login screen.
5. WHEN a User selects logout, THE Auth_Service SHALL invalidate the current Supabase Auth session and THE Auth_Controller SHALL navigate the User to the login screen.

---

### Requirement 3: Campus Map Display

**User Story:** As a User, I want to see an interactive map of the BOUESTI campus with labelled building markers, so that I can visually orient myself and find locations.

#### Acceptance Criteria

1. WHEN the Campus Map screen loads, THE Map_Controller SHALL fetch all Location records from the `locations` table via the Campus_Repository and render a Google Maps view centred on BOUESTI's geographic coordinates.
2. THE Map_Controller SHALL place a distinct marker on the Google Map for each Location record, positioned at the Location's `lat` and `lng` coordinates.
3. WHEN a User taps a map marker, THE Map_Controller SHALL display an info panel showing the Location's `name`, `department`, and `hours` fields.
4. WHILE the User's device GPS is active and permissions are granted, THE Location_Service SHALL continuously update the User's position and THE Map_Controller SHALL display a live position indicator on the map.
5. IF the Campus_Repository fails to fetch Location records due to a network error, THEN THE Map_Controller SHALL display an error banner and a retry option while continuing to display any previously cached Location markers without crashing.
6. THE Map_Controller SHALL re-fetch Location records from the Campus_Repository without requiring an app restart when new locations are added by an Admin.

---

### Requirement 4: Campus Graph Construction

**User Story:** As a system component, I want the campus walkable path network to be represented as a weighted graph, so that Dijkstra's algorithm can compute optimal routes.

#### Acceptance Criteria

1. WHEN the Routing_Service is initialised, THE Routing_Service SHALL fetch all Location records and all Edge records from Supabase via the Campus_Repository and construct an in-memory adjacency-list graph.
2. THE Routing_Service SHALL represent each Location as a Graph_Node with an identifier, name, latitude, and longitude.
3. THE Routing_Service SHALL represent each Edge as a weighted connection between two Graph_Nodes with a weight equal to `distance_meters`.
4. IF any Edge references a `from_location_id` or `to_location_id` that does not exist in the fetched Location records, THEN THE Routing_Service SHALL log the inconsistency and exclude the malformed Edge from the graph without failing initialisation.
5. WHEN the Campus_Repository notifies the Routing_Service of a Location or Edge change, THE Routing_Service SHALL queue any incoming route computation requests and rebuild the graph to reflect the updated data before processing the queued requests.

---

### Requirement 5: Route Computation

**User Story:** As a User, I want the app to compute the shortest walking path between my current location and a chosen destination, so that I can navigate efficiently across campus.

#### Acceptance Criteria

1. WHEN a User selects a destination Location, THE Navigation_Controller SHALL pass the User's current GPS coordinates and the destination Location's identifier to the Routing_Service.
2. THE Routing_Service SHALL identify the Graph_Node nearest to the User's current GPS coordinates as the route origin.
3. THE Routing_Service SHALL execute Dijkstra's algorithm on the campus graph and return the Route with the minimum total `distance_meters` from origin to destination.
4. IF no path exists between the origin Graph_Node and the destination Graph_Node, THEN THE Routing_Service SHALL return an empty Route result and THE Navigation_Controller SHALL independently detect the absence of a valid Route and display a message stating no navigable path was found, regardless of whether the Routing_Service explicitly signals an error.
5. THE Navigation_Controller SHALL render the computed Route as a polyline overlay on the Google Map.
6. THE Navigation_Controller SHALL generate an ordered list of Turn_Instructions from the Route's Graph_Node sequence.
7. FOR ALL valid origin–destination pairs where a path exists, the Route total distance returned by the Routing_Service SHALL equal the sum of the `distance_meters` values of the Route's constituent Edges (path-weight consistency property).
8. FOR ALL valid destination Graph_Nodes, computing a Route and then computing a Route in the reverse direction SHALL yield the same total `distance_meters` when all Edges are undirected (symmetry property).

---

### Requirement 6: Turn-by-Turn Navigation

**User Story:** As a User, I want step-by-step directional instructions as I walk, so that I can follow the route without constantly looking at the screen.

#### Acceptance Criteria

1. WHEN a Route is active, THE Navigation_Controller SHALL display the current Turn_Instruction prominently on the navigation screen.
2. WHEN the User's GPS position advances past a Graph_Node waypoint, THE Navigation_Controller SHALL automatically advance to the next Turn_Instruction in the sequence.
3. THE Navigation_Controller SHALL display the estimated remaining distance to the destination, updated with each GPS position change.
4. WHEN the User reaches the destination Graph_Node within a 15-metre radius, THE Navigation_Controller SHALL mark the Route as complete and display an arrival confirmation.
5. WHEN a User cancels active navigation, THE Navigation_Controller SHALL clear the Route polyline, stop GPS tracking callbacks, and return the User to the Campus Map screen.

---

### Requirement 7: Automatic Rerouting on Deviation

**User Story:** As a User, I want the app to recalculate my route if I stray from the path, so that I can always find my way back without manual intervention.

#### Acceptance Criteria

1. WHILE a Route is active, THE Navigation_Controller SHALL monitor the User's live GPS position against the active Route's polyline.
2. WHEN the User's GPS position deviates more than 30 metres from the nearest point on the active Route polyline, THE Navigation_Controller SHALL trigger a reroute.
3. WHEN a reroute is triggered, THE Routing_Service SHALL compute a new Route from the User's current GPS position to the original destination and THE Navigation_Controller SHALL replace the active Route with the new Route.
4. WHEN a reroute is triggered, THE Voice_Controller SHALL speak a rerouting notification to the User via TTS.
5. IF the Routing_Service fails to compute a new Route during a reroute attempt, THEN THE Navigation_Controller SHALL display an error message and retain the previous Route until a successful reroute is available.

---

### Requirement 8: Voice Destination Search (STT)

**User Story:** As a User, I want to speak a destination name and have the app find and navigate to it, so that I can operate the app completely hands-free.

#### Acceptance Criteria

1. WHEN a User activates the voice search control, THE Voice_Controller SHALL invoke the Voice_Service to begin an STT listening session using the device microphone.
2. WHEN the STT session captures speech, THE Voice_Service SHALL convert the captured audio to a text string and return it to the Voice_Controller.
3. WHEN a text string is produced by STT, THE Voice_Controller SHALL pass it to the Campus_Repository to search for a matching Location by name.
4. THE Campus_Repository SHALL perform a case-insensitive partial-match search against the `name` field of all Location records when given a text query.
5. IF no matching Location is found for the STT text, THEN THE Voice_Controller SHALL trigger a TTS response informing the User that no matching location was found and prompt the User to try again.
6. WHEN exactly one matching Location is found, THE Navigation_Controller SHALL begin route computation to that Location.
7. WHEN multiple matching Locations are found, THE Voice_Controller SHALL list the matching names audibly via TTS and display them on screen for the User to select.
8. IF the device microphone permission is not granted, THEN THE Voice_Controller SHALL display a permission request dialog explaining why microphone access is needed.

---

### Requirement 9: Spoken Turn-by-Turn Directions (TTS)

**User Story:** As a User, I want the app to read each navigation instruction aloud as I approach each turn, so that I can keep my phone in my pocket while navigating.

#### Acceptance Criteria

1. WHEN a new Turn_Instruction becomes active during navigation, THE Voice_Controller SHALL invoke the Voice_Service to speak the Turn_Instruction text via TTS.
2. THE Voice_Service SHALL queue TTS utterances so that a new instruction does not interrupt an utterance that is still playing; the new instruction SHALL be spoken immediately after the current utterance completes.
3. WHEN the User reaches the destination, THE Voice_Controller SHALL speak an arrival confirmation message via TTS.
4. WHEN a reroute occurs, THE Voice_Controller SHALL speak the rerouting notification before speaking the first instruction of the new Route.
5. WHEN a User mutes voice output, THE Voice_Controller SHALL stop all ongoing and queued TTS utterances and suppress further TTS invocations until the User unmutes.
6. WHEN the User unmutes voice output, THE Voice_Controller SHALL resume speaking Turn_Instructions from the current active step.

---

### Requirement 10: Admin Location Management

**User Story:** As an Admin, I want to create, update, and delete campus location records through an in-app dashboard, so that the campus map stays accurate without requiring code changes or app redeployment.

#### Acceptance Criteria

1. WHEN a User whose Profile has `is_admin = true` logs in, THE App SHALL display an Admin dashboard navigation entry that is not visible to non-admin Users.
2. THE Admin_Controller SHALL fetch all Location records and display them in a list on the admin dashboard.
3. WHEN an Admin submits a new Location form with `name`, `department`, `lat`, `lng`, and `hours` values, THE Admin_Controller SHALL insert a new row into the `locations` table via Supabase and THE Map_Controller SHALL reflect the new Location on the campus map.
4. WHEN an Admin selects an existing Location and submits an edit form, THE Admin_Controller SHALL update the corresponding row in the `locations` table via Supabase.
5. WHEN an Admin confirms deletion of a Location, THE Admin_Controller SHALL execute an atomic transaction that deletes the associated Edge rows and the Location row together; IF the Edge deletion fails, THEN THE Admin_Controller SHALL roll back the Location deletion and display an error message stating nothing was deleted.
6. IF a non-admin User attempts to write to the `locations` or `edges` tables directly via the Supabase client, THEN THE Supabase RLS policies SHALL reject the operation with a permission error.
7. IF an Admin submits a Location form with a missing required field (`name`, `lat`, or `lng`), THEN THE Admin_Controller SHALL display a validation error and prevent submission.

---

### Requirement 11: Admin Edge Management

**User Story:** As an Admin, I want to define walkable path connections between campus locations, so that the routing graph reflects real navigable routes on campus.

#### Acceptance Criteria

1. THE Admin_Controller SHALL provide a form for creating a new Edge by selecting a `from_location_id`, a `to_location_id`, and entering a `distance_meters` value.
2. WHEN an Admin submits a valid Edge form, THE Admin_Controller SHALL insert a new row into the `edges` table via Supabase and THE Routing_Service SHALL incorporate the new Edge into the campus graph.
3. WHEN an Admin deletes an Edge, THE Admin_Controller SHALL delete the corresponding row from the `edges` table and THE Routing_Service SHALL rebuild the graph excluding the deleted Edge.
4. IF an Admin submits an Edge form with a `distance_meters` value of zero or less, THEN THE Admin_Controller SHALL display a validation error and prevent submission.
5. IF an Admin submits an Edge form where `from_location_id` equals `to_location_id`, THEN THE Admin_Controller SHALL display a validation error stating self-loops are not allowed.

---

### Requirement 12: Data-Driven Location Updates Without Code Changes

**User Story:** As an Admin, I want adding or editing locations to be reflected in the live app immediately, so that the campus map is always up to date without app store redeployment.

#### Acceptance Criteria

1. WHEN a Location record is inserted, updated, or deleted in the `locations` Supabase table, THE Map_Controller SHALL update the campus map markers to reflect the change without requiring an app restart.
2. WHEN an Edge record is inserted or deleted in the `edges` Supabase table, THE Routing_Service SHALL rebuild the in-memory campus graph to incorporate the change without requiring an app restart.
3. THE Campus_Repository SHALL expose a refresh mechanism that the Map_Controller and Routing_Service can call to re-fetch updated data from Supabase.

---

### Requirement 13: GPS Location Permission Handling

**User Story:** As a User, I want the app to clearly request location permission and explain why it is needed, so that I can make an informed decision and the app functions correctly if I grant it.

#### Acceptance Criteria

1. WHEN the App is first launched, THE Location_Service SHALL request foreground location permission from the operating system before attempting to read GPS coordinates.
2. IF the User denies location permission, THEN THE Location_Service SHALL notify the Map_Controller and THE Map_Controller SHALL display the campus map in a browse-only mode without live position tracking or active navigation.
3. IF the User denies location permission, THEN THE Navigation_Controller SHALL display a message stating live navigation is unavailable without location access and provide a link to the device settings to grant the permission.
4. WHEN the User grants location permission after initial denial, THE Location_Service SHALL begin GPS tracking without requiring an app restart.

---

### Requirement 14: Offline and Error Resilience

**User Story:** As a User, I want the app to handle network errors gracefully, so that I am never left with a blank screen or a crash.

#### Acceptance Criteria

1. IF the App cannot reach Supabase on startup, THEN THE Campus_Repository SHALL return the last successfully cached Location and Edge data and THE Map_Controller SHALL display the cached data with a banner indicating the data may be outdated.
2. IF no cached data is available and Supabase is unreachable, THEN THE Map_Controller SHALL display an informative message stating the map data could not be loaded and provide a retry option.
3. IF the Google Maps SDK fails to render the map tile, THEN THE Map_Controller SHALL display an error message without crashing the App.
4. WHILE navigating, IF the device loses GPS signal, THEN THE Navigation_Controller SHALL display a message stating GPS signal is lost and pause rerouting until the signal is restored.
