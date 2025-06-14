import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class ResultsScreen extends StatelessWidget {
  final String from;
  final String to;

  const ResultsScreen({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        iconTheme: const IconThemeData(color: AppColors.gold),
        title: const Text(
          "Résultats",
          style: TextStyle(color: AppColors.gold, fontFamily: 'PlayfairDisplay'),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Votre recherche",
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _infoCard("Départ", from),
            const SizedBox(height: 12),
            _infoCard("Destination", to),
            const SizedBox(height: 32),
            const Center(
              child: Text(
                "Aucun trajet trouvé pour l’instant.",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: 1),
      ),
      child: Row(
        children: [
          Text(
            "$label : ",
            style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
