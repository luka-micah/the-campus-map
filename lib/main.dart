import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/campus_repository.dart';
import 'data/supabase_campus_repository.dart';
import 'data/supabase_service.dart';
import 'core/models/edge_model.dart';
import 'core/models/location_model.dart';
import 'features/auth/auth_binding.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/views/login_view.dart';
import 'features/auth/views/register_view.dart';
import 'features/admin/admin_binding.dart';
import 'features/admin/views/admin_dashboard_view.dart';
import 'features/map/map_binding.dart';
import 'features/map/views/map_view.dart';
import 'features/navigation/navigation_binding.dart';
import 'features/navigation/views/navigation_view.dart';
import 'routing/routing_service.dart';

/// Named route constants used throughout the app via [Get.toNamed].
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String register = '/register';
  static const String map = '/map';
  static const String navigation = '/navigation';
  static const String admin = '/admin';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootClock = Stopwatch()..start();

  // Initialize SharedPreferences first
  final prefs = await SharedPreferences.getInstance();
  Get.put<SharedPreferences>(prefs, permanent: true);

  // Initialize Supabase
  final supabaseService = SupabaseService.instance;
  await supabaseService.initialise();
  debugPrint('Startup: Supabase ready at ${bootClock.elapsedMilliseconds}ms');

  // Initialize CampusRepository and fetch initial data
  final campusRepository = SupabaseCampusRepository(
    supabaseService: supabaseService,
    prefs: prefs,
  );
  Get.put<CampusRepository>(campusRepository, permanent: true);

  // Initialize RoutingService
  final routingService = RoutingService();
  Get.put<RoutingService>(routingService, permanent: true);

  // Initialize AuthController and restore session (no navigation here —
  // GetMaterialApp doesn't exist yet, so navigation would crash).
  final authController = AuthController(supabaseService: supabaseService);
  Get.put<AuthController>(authController, permanent: true);

  // Build initial routing graph + restore session CONCURRENTLY instead of
  // one network round-trip after another: on mobile data each await can
  // cost seconds, and runApp (first frame) waits for all of them. Every
  // leg is individually bounded and failure-tolerant — cached data and the
  // login screen are always reachable, so startup degrades instead of
  // hanging on a slow network.
  List<LocationModel> locations = const [];
  List<EdgeModel> edges = const [];
  await Future.wait([
    _startupLeg(
      'locations',
      () async {
        locations = await campusRepository.fetchLocations();
      },
      bootClock,
    ),
    _startupLeg(
      'edges',
      () async {
        edges = await campusRepository.fetchEdges();
      },
      bootClock,
    ),
    _startupLeg(
      'session',
      authController.restoreSession,
      bootClock,
    ),
  ]);
  routingService.buildGraph(locations, edges);
  final bool hasSession = authController.currentUser.value != null;
  debugPrint(
    'Startup: first frame at ${bootClock.elapsedMilliseconds}ms '
    '(${locations.length} locations, ${edges.length} edges, '
    'session=$hasSession)',
  );

  // Subscribe to Realtime updates
  routingService.subscribeToRealtimeUpdates(campusRepository);

  runApp(CampusMapApp(initialRoute: hasSession ? AppRoutes.map : AppRoutes.login));
}

/// Runs one startup leg with a hard deadline. Network failures, timeouts,
/// and missing caches all resolve to "skip this leg" — the repository
/// serves cached data where it can, and the app boots to login regardless.
Future<void> _startupLeg(
  String name,
  Future<void> Function() task,
  Stopwatch bootClock, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    await task().timeout(timeout);
    debugPrint('Startup: $name ready at ${bootClock.elapsedMilliseconds}ms');
  } catch (e) {
    // Tolerate offline / unconfigured Supabase so the app still boots to
    // login instead of crashing (e.g. placeholder 'your-project.supabase.co').
    debugPrint('Startup: $name unavailable, continuing offline ($e)');
  }
}

class CampusMapApp extends StatelessWidget {
  const CampusMapApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'BOUESTI Campus Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      getPages: [
        GetPage(
          name: AppRoutes.login,
          page: () => LoginView(),
          binding: AuthBinding(),
        ),
        GetPage(
          name: AppRoutes.register,
          page: () => RegisterView(),
          binding: AuthBinding(),
        ),
        GetPage(
          name: AppRoutes.map,
          page: () => MapView(),
          binding: MapBinding(),
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name: AppRoutes.navigation,
          page: () => NavigationView(),
          binding: NavigationBinding(),
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name: AppRoutes.admin,
          page: () => AdminDashboardView(),
          binding: AdminBinding(),
          middlewares: [AuthMiddleware(), AdminMiddleware()],
        ),
      ],
    );
  }
}

class AuthMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    final authController = Get.find<AuthController>();
    if (authController.currentUser.value == null) {
      return const RouteSettings(name: AppRoutes.login);
    }
    return null;
  }
}

class AdminMiddleware extends GetMiddleware {
  @override
  int? get priority => 2;

  @override
  RouteSettings? redirect(String? route) {
    final authController = Get.find<AuthController>();
    if (authController.currentUser.value == null ||
        authController.isAdmin.value != true) {
      return const RouteSettings(name: AppRoutes.map);
    }
    return null;
  }
}