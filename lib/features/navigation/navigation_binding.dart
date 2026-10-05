import 'package:get/get.dart';

import '../../data/campus_repository.dart';
import '../../data/supabase_campus_repository.dart';
import '../../data/supabase_service.dart';
import '../../routing/routing_service.dart';
import '../map/location_service.dart';
import '../voice/voice_controller.dart';
import '../voice/voice_service.dart';
import 'navigation_controller.dart';

class NavigationBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SupabaseService>(() => SupabaseService.instance);
    Get.lazyPut<CampusRepository>(
      () => SupabaseCampusRepository(
        supabaseService: Get.find(),
        prefs: Get.find(),
      ),
    );
    Get.lazyPut<LocationService>(() => LocationService());
    Get.lazyPut<RoutingService>(() => RoutingService());
    // Registered here (not only in VoiceBinding, which no route uses):
    // NavigationController needs a VoiceController, which needs this.
    Get.lazyPut<VoiceService>(() => VoiceService());
    Get.lazyPut<VoiceController>(
      () => VoiceController(
        voiceService: Get.find(),
        campusRepository: Get.find(),
      ),
    );
    Get.lazyPut<NavigationController>(
      () => NavigationController(
        campusRepository: Get.find(),
        locationService: Get.find(),
        voiceController: Get.find(),
        routingService: Get.find(),
      ),
    );
  }
}