import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:the_campus_map/core/models/edge_model.dart';
import 'package:the_campus_map/core/models/location_model.dart';
import 'package:the_campus_map/data/campus_repository.dart';
import 'package:the_campus_map/features/admin/admin_controller.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockCampusRepository extends Mock implements CampusRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

LocationModel _loc(
  String id,
  String name, {
  double lat = 7.0,
  double lng = 5.0,
}) =>
    LocationModel(
      id: id,
      name: name,
      department: 'Dept',
      lat: lat,
      lng: lng,
      hours: '',
      createdAt: DateTime(2024),
    );

EdgeModel _edge(String id, String from, String to, double dist) => EdgeModel(
      id: id,
      fromLocationId: from,
      toLocationId: to,
      distanceMeters: dist,
    );

// ---------------------------------------------------------------------------
// Tests — Requirement 10: Admin Location Management
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;

  // mocktail needs valid model instances for any() matchers.
  setUpAll(() {
    registerFallbackValue(
      LocationModel(
        id: 'fallback',
        name: 'fallback',
        department: '',
        lat: 0,
        lng: 0,
        hours: '',
        createdAt: DateTime(2024),
      ),
    );
    registerFallbackValue(
      const EdgeModel(
        id: 'fallback',
        fromLocationId: 'a',
        toLocationId: 'b',
        distanceMeters: 1,
      ),
    );
  });

  late MockCampusRepository repo;
  late AdminController sut;

  setUp(() {
    repo = MockCampusRepository();
    sut = AdminController(campusRepository: repo);
  });

  group('Requirement 10.2: dashboard lists all locations', () {
    test('loadData populates locations and edges', () async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.fetchEdges())
          .thenAnswer((_) async => [_edge('e1', 'a', 'b', 10.0)]);

      await sut.loadData();

      expect(sut.locations.map((l) => l.id).toList(), ['a']);
      expect(sut.edges.map((e) => e.id).toList(), ['e1']);
      expect(sut.errorMessage.value, isEmpty);
    });
  });

  group('Requirement 10.3/10.4: create and update locations', () {
    test('valid create inserts and refreshes', () async {
      when(() => repo.insertLocation(any()))
          .thenAnswer((_) async {});
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.fetchEdges()).thenAnswer((_) async => []);

      await sut.createLocation(_loc('', 'Alpha'));

      verify(() => repo.insertLocation(any())).called(1);
      expect(sut.locations, hasLength(1));
      expect(sut.errorMessage.value, isEmpty);
    });

    test('update calls updateLocation, never insertLocation', () async {
      when(() => repo.updateLocation(any()))
          .thenAnswer((_) async {});
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha v2')]);
      when(() => repo.fetchEdges()).thenAnswer((_) async => []);

      await sut.updateLocation(_loc('a', 'Alpha v2'));

      verify(() => repo.updateLocation(any())).called(1);
      verifyNever(() => repo.insertLocation(any()));
      expect(sut.errorMessage.value, isEmpty);
    });
  });

  group('Requirement 10.7: location validation', () {
    test('whitespace-only name is rejected without a repository call',
        () async {
      await sut.createLocation(_loc('', '   '));

      expect(sut.errorMessage.value, isNotEmpty);
      verifyNever(() => repo.insertLocation(any()));
      expect(sut.locations, isEmpty);
    });

    test('NaN coordinates are rejected without a repository call', () async {
      await sut.createLocation(_loc('', 'Alpha', lat: double.nan));

      expect(sut.errorMessage.value, isNotEmpty);
      verifyNever(() => repo.insertLocation(any()));
    });

    test('out-of-range coordinates are rejected without a repository call',
        () async {
      await sut.createLocation(_loc('', 'Alpha', lat: 200.0));
      expect(sut.errorMessage.value, isNotEmpty);

      sut.errorMessage.value = '';
      await sut.createLocation(_loc('', 'Alpha', lng: -200.0));
      expect(sut.errorMessage.value, isNotEmpty);

      verifyNever(() => repo.insertLocation(any()));
    });
  });

  group('Requirement 10.5: atomic delete', () {
    Future<void> preload() async {
      when(() => repo.fetchLocations())
          .thenAnswer((_) async => [_loc('a', 'Alpha')]);
      when(() => repo.fetchEdges()).thenAnswer((_) async => []);
      await sut.loadData();
    }

    test('successful delete refreshes the list', () async {
      await preload();
      when(() => repo.deleteLocation(any())).thenAnswer((_) async {});
      // Reload after delete returns the remaining rows.
      when(() => repo.fetchLocations()).thenAnswer((_) async => []);

      await sut.deleteLocation('a');

      verify(() => repo.deleteLocation('a')).called(1);
      expect(sut.locations, isEmpty);
      expect(sut.errorMessage.value, isEmpty);
    });

    test('failed delete reports that nothing was deleted', () async {
      await preload();
      when(() => repo.deleteLocation(any()))
          .thenThrow(Exception('permission denied'));

      await sut.deleteLocation('a');

      // 10.5: the single-statement delete is atomic, so failure means the
      // local list is untouched and the message says so.
      expect(sut.errorMessage.value, contains('Nothing was deleted'));
      expect(sut.locations.map((l) => l.id).toList(), ['a']);
    });
  });

  group('Requirement 11 edge validation (admin edge forms)', () {
    Future<void> preload() async {
      when(() => repo.fetchLocations()).thenAnswer(
        (_) async => [_loc('a', 'Alpha'), _loc('b', 'Beta')],
      );
      when(() => repo.fetchEdges()).thenAnswer((_) async => []);
      await sut.loadData();
    }

    test('zero or negative distance is rejected without a repository call',
        () async {
      await preload();

      await sut.createEdge(_edge('', 'a', 'b', 0));
      expect(sut.errorMessage.value, isNotEmpty);

      sut.errorMessage.value = '';
      await sut.createEdge(_edge('', 'a', 'b', -25.5));
      expect(sut.errorMessage.value, isNotEmpty);

      verifyNever(() => repo.insertEdge(any()));
    });

    test('self-loop is rejected without a repository call', () async {
      await preload();

      await sut.createEdge(_edge('', 'a', 'a', 10.0));

      expect(sut.errorMessage.value, contains('Self-loop'));
      verifyNever(() => repo.insertEdge(any()));
    });

    test('unknown location ids are rejected without a repository call',
        () async {
      await preload();

      await sut.createEdge(_edge('', 'a', 'ghost', 10.0));

      expect(sut.errorMessage.value, isNotEmpty);
      verifyNever(() => repo.insertEdge(any()));
    });

    test('valid edge inserts and refreshes', () async {
      await preload();
      when(() => repo.insertEdge(any())).thenAnswer((_) async {});
      when(() => repo.fetchEdges()).thenAnswer(
        (_) async => [_edge('e1', 'a', 'b', 10.0)],
      );

      await sut.createEdge(_edge('', 'a', 'b', 10.0));

      verify(() => repo.insertEdge(any())).called(1);
      expect(sut.edges, hasLength(1));
      expect(sut.errorMessage.value, isEmpty);
    });

    test('edge edit calls updateEdge, never insertEdge', () async {
      await preload();
      when(() => repo.updateEdge(any())).thenAnswer((_) async {});
      when(() => repo.fetchEdges()).thenAnswer(
        (_) async => [_edge('e1', 'a', 'b', 20.0)],
      );

      await sut.updateEdge(_edge('e1', 'a', 'b', 20.0));

      verify(() => repo.updateEdge(any())).called(1);
      verifyNever(() => repo.insertEdge(any()));
      expect(sut.errorMessage.value, isEmpty);
    });
  });
}
