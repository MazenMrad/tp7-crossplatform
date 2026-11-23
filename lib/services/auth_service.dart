import '../models/app_user.dart';

/// Testable abstraction over Supabase Auth.
abstract class AuthService {
  AppUser? get currentUser;
  Stream<AppUser?> get authStateChanges;

  Future<void> signIn({required String email, required String password});
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  });
  Future<void> signOut();
}
