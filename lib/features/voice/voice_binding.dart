import 'package:get/get.dart';

import '../../data/campus_repository.dart';
import '../../data/supabase_campus_repository.dart';
import '../../data/supabase_service.dart';
import 'voice_controller.dart';
import 'voice_service.dart';

class VoiceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SupabaseService>(() => SupabaseService.instance);
    Get.lazyPut<CampusRepository>(
      () => SupabaseCampusRepository(
        supabaseService: Get.find(),
        prefs: Get.find(),
      ),
    );
    Get.lazyPut<VoiceService>(() => VoiceService());
    Get.lazyPut<VoiceController>(
      () => VoiceController(
        voiceService: Get.find(),
        campusRepository: Get.find(),
      ),
    );
  }
}