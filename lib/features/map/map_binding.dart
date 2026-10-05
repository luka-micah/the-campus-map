import 'package:get/get.dart';

import '../../data/campus_repository.dart';
import '../../data/supabase_campus_repository.dart';
import '../../data/supabase_service.dart';
import '../../routing/routing_service.dart';
import '../voice/voice_controller.dart';
import '../voice/voice_service.dart';
import 'location_service.dart';
import 'map_controller.dart';

class MapBinding extends Bindings {
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
    // Voice search control lives on the map screen (8.1).
    Get.lazyPut<VoiceService>(() => VoiceService());
    Get.lazyPut<VoiceController>(
      () => VoiceController(
        voiceService: Get.find(),
        campusRepository: Get.find(),
      ),
    );
    Get.lazyPut<MapController>(
      () => MapController(
        campusRepository: Get.find(),
        locationService: Get.find(),
        routingService: Get.find(),
      ),
    );
  }
}