import 'package:get/get.dart';

import '../../data/campus_repository.dart';
import '../../data/supabase_campus_repository.dart';
import '../../data/supabase_service.dart';
import 'admin_controller.dart';

class AdminBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SupabaseService>(() => SupabaseService.instance);
    Get.lazyPut<CampusRepository>(
      () => SupabaseCampusRepository(
        supabaseService: Get.find(),
        prefs: Get.find(),
      ),
    );
    Get.lazyPut<AdminController>(
      () => AdminController(campusRepository: Get.find()),
    );
  }
}