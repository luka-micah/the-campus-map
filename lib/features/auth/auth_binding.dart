import 'package:get/get.dart';

import '../../data/supabase_service.dart';
import 'auth_controller.dart';
import 'auth_service.dart';

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SupabaseService>(() => SupabaseService.instance);
    Get.lazyPut<AuthService>(() => AuthService(supabaseService: Get.find()));
    Get.lazyPut<AuthController>(
      () => AuthController(supabaseService: Get.find()),
    );
  }
}