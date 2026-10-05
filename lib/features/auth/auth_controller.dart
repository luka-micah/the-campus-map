import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import '../../data/supabase_service.dart';

class AuthController extends GetxController {
  final AuthService _authService;

  AuthController({required SupabaseService supabaseService})
      : _authService = AuthService(supabaseService: supabaseService);

  Rx<User?> get currentUser => _authService.currentUser;
  RxString get errorMessage => _authService.errorMessage;
  RxBool get isLoading => _authService.isLoading;
  RxBool get isAdmin => _authService.isAdmin;

  Future<void> register(String username, String email, String password) async {
    await _authService.register(username, email, password);
    if (errorMessage.value.isEmpty && currentUser.value != null) {
      Get.offAllNamed('/map');
    }
  }

  Future<void> login(String email, String password) async {
    await _authService.login(email, password);
    if (errorMessage.value.isEmpty && currentUser.value != null) {
      Get.offAllNamed('/map');
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    if (currentUser.value == null) {
      Get.offAllNamed('/login');
    }
  }

  Future<void> restoreSession() async {
    // Pure restore only — must NOT navigate here. main() calls this BEFORE
    // runApp(), when no GetMaterialApp exists yet, so Get.offAllNamed would
    // throw "contextless navigation without a GetMaterialApp". Navigation
    // is handled via initialRoute in CampusMapApp instead.
    await _authService.restoreSession();
  }
}