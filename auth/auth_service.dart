import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Sign Up
  Future<AuthResponse> signUp(String email, String password) async {
    final response = await _supabase.auth.signUp(email: email, password: password);
    return response;
  }

  // Sign In
  Future<AuthResponse> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(email: email, password: password);
    return response;
  }

  // Sign Out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Get Current User
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }
}
