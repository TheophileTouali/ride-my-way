import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class SearchDestinationScreen extends StatelessWidget {
  const SearchDestinationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
        title: const Text("Où souhaitez-vous aller ?"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Saisir une destination",
                hintStyle: const TextStyle(color: Colors.white60),
                prefixIcon: const Icon(Icons.search, color: AppColors.gold),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onSubmitted: (value) {
                // Rediriger vers les résultats ou suggestions
                context.go('/results?destination=$value');
              },
            ),
            const SizedBox(height: 32),
            const Text("Suggestions :", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ListTile(
              title: const Text("Paris", style: TextStyle(color: Colors.white)),
              onTap: () => context.go('/results?destination=Paris'),
            ),
            ListTile(
              title: const Text("Aéroport Charles de Gaulle", style: TextStyle(color: Colors.white)),
              onTap: () => context.go('/results?destination=CDG'),
            ),
          ],
        ),
      ),
    );
  }
}
