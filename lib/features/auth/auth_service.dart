import 'package:flutter/foundation.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_state_manager/get_state_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../data/supabase_service.dart';

class AuthService extends GetxService {
  final SupabaseService _supabaseService;

  final Rx<User?> currentUser = Rx<User?>(null);
  final RxString errorMessage = RxString('');
  final RxBool isLoading = RxBool(false);
  final RxBool isAdmin = RxBool(false);

  AuthService({required SupabaseService supabaseService})
      : _supabaseService = supabaseService;

  Future<void> register(String username, String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final authResponse = await _supabaseService.client.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        errorMessage.value = 'Registration failed. Please try again.';
        return;
      }

      // Email-confirmation ON: Supabase creates the auth.users row but returns
      // NO session until the user clicks the email link. Inserting into
      // `profiles` now would fail RLS (auth.uid() is null), leaving an auth
      // user with no profile row — exactly the "email exists but profiles
      // empty, login fails" state. Bail out with a clear message instead.
      if (authResponse.session == null) {
        await _supabaseService.client.auth.signOut();
        errorMessage.value =
            'Account created. Check your email to confirm, then log in. '
            '(Or turn off "Confirm email" in Supabase Auth settings for testing.)';
        return;
      }

      final profile = UserProfile(
        id: user.id,
        username: username,
        isAdmin: false,
      );

      try {
        final response = await _supabaseService.client
            .from('profiles')
            .insert(profile.toJson())
            .select();

        if (response.isEmpty) {
          await _supabaseService.client.auth.signOut();
          errorMessage.value = 'Profile creation failed. Please try again.';
          return;
        }
      } on PostgrestException catch (e) {
        debugPrint('Profile insert failed: ${e.code} ${e.message}');
        await _supabaseService.client.auth.signOut();
        final msg = e.message.toLowerCase();
        if (msg.contains('duplicate') || msg.contains('unique')) {
          errorMessage.value = 'That username is already taken.';
        } else if (e.code == '42501' || msg.contains('row-level security')) {
          errorMessage.value =
              'Signup blocked by database policy (RLS). Run the migration in supabase/migrations/ and check Auth > Confirm email setting.';
        } else if (msg.contains('profiles') && msg.contains('does not exist')) {
          errorMessage.value =
              'The profiles table does not exist. Run supabase/migrations/20261001000000_create_campus_schema.sql in the SQL Editor.';
        } else {
          errorMessage.value = 'Profile creation failed: ${e.message}';
        }
        return;
      }

      currentUser.value = user;
    } on AuthException catch (e) {
      _handleAuthException(e);
    } catch (e) {
      debugPrint('Register unexpected error: $e');
      errorMessage.value = 'An unexpected error occurred.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login(String email, String password) async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final response = await _supabaseService.client.auth
          .signInWithPassword(
        email: email,
        password: password,
      );
      currentUser.value = response.user;
      if (response.user != null) {
        // Query only our own profile — cheaper and doesn't require a
        // permissive "read all profiles" policy to succeed.
        try {
          final row = await _supabaseService.client
              .from('profiles')
              .select()
              .eq('id', response.user!.id)
              .maybeSingle();
          if (row != null) {
            isAdmin.value = UserProfile.fromJson(row).isAdmin;
          } else {
            isAdmin.value = false;
            debugPrint(
                'Login: no profiles row for ${response.user!.id} — user registered but profile insert never succeeded.');
          }
        } catch (e) {
          debugPrint('Login profile lookup failed (non-fatal): $e');
          isAdmin.value = false;
        }
      }
    } on AuthException catch (e) {
      _handleAuthException(e);
    } catch (e) {
      debugPrint('Login unexpected error: $e');
      errorMessage.value = 'Invalid credentials.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await _supabaseService.client.auth.signOut();
      currentUser.value = null;
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      errorMessage.value = 'Logout failed.';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> restoreSession() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final session = _supabaseService.client.auth.currentSession;
      final user = session?.user ?? _supabaseService.client.auth.currentUser;
      if (user == null) return;
      currentUser.value = user;
      try {
        final row = await _supabaseService.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (row != null) {
          isAdmin.value = UserProfile.fromJson(row).isAdmin;
        }
      } catch (e) {
        debugPrint('restoreSession profile lookup failed (non-fatal): $e');
      }
    } on AuthException catch (e) {
      errorMessage.value = e.message;
    } catch (e) {
      debugPrint('restoreSession error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _handleAuthException(AuthException e) {
    debugPrint('AuthException: code=${e.code} message=${e.message}');
    final message = e.message.toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('already been registered') ||
        message.contains('duplicate')) {
      errorMessage.value =
          'An account with that email already exists. Try logging in instead. '
          'If profiles is empty, delete the stale user in Dashboard > Authentication > Users and register again.';
    } else if (message.contains('email not confirmed') ||
        message.contains('not confirmed') ||
        message.contains('confirm')) {
      errorMessage.value =
          'Email not confirmed. Check your inbox for the confirmation link, or turn off "Confirm email" in Supabase Auth settings for testing.';
    } else if (message.contains('invalid login') ||
        message.contains('invalid credentials')) {
      errorMessage.value =
          'Invalid email or password. If you just registered, the account may not exist yet — check the exact error in the logs.';
    } else if (message.contains('username') &&
        (message.contains('duplicate') ||
            message.contains('already') ||
            message.contains('unique'))) {
      errorMessage.value = 'A user with that username already exists.';
    } else if (message.contains('password') || message.contains('weak')) {
      errorMessage.value = 'Password must be at least 8 characters.';
    } else {
      // Show the REAL Supabase message (e.g. "Email signups are disabled",
      // "Error sending confirmation email") instead of masking it as
      // "email already exists".
      errorMessage.value = e.message;
    }
  }
}
