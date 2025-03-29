// home_screen.dart
import 'package:flutter/material.dart';
import 'package:/supabase_flutter/supabase_flutter.dart'; // Import AuthService

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService(); // In a larger app, consider using dependency injection

    return Scaffold(
      appBar: AppBar(title: const Text("Home")),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await authService.signOut();
          },
          child: const Text("Sign Out"),
        ),
      ),
    );
  }
}