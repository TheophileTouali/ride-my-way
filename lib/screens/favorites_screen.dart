import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import '../themes/app_theme.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  String selectedFilter = "Tous";

  final List<Map<String, String>> favorites = const [
    {"from": "Paris", "to": "Lyon", "frequency": "Hebdomadaire"},
    {"from": "Créteil", "to": "Orly Aéroport", "frequency": "Quotidienne"},
    {"from": "Nanterre", "to": "Versailles", "frequency": "Mensuelle"},
    {"from": "La Défense", "to": "Roissy CDG", "frequency": "Ponctuelle"},
    {"from": "Boulogne", "to": "Champs-Élysées", "frequency": "Hebdomadaire"},
    {"from": "Ivry-sur-Seine", "to": "Montreuil", "frequency": "Quotidienne"},
    {"from": "Clamart", "to": "Saint-Denis", "frequency": "Hebdomadaire"},
    {"from": "Courbevoie", "to": "Gare de Lyon", "frequency": "Mensuelle"},
    {"from": "Rueil-Malmaison", "to": "Massy", "frequency": "Hebdomadaire"},
    {"from": "Vitry", "to": "Gare Montparnasse", "frequency": "Quotidienne"},
    {"from": "Melun", "to": "Paris", "frequency": "Ponctuelle"},
    {"from": "Saint-Maur", "to": "Val d'Europe", "frequency": "Hebdomadaire"},
  ];

  @override
  Widget build(BuildContext context) {
    final filteredFavorites = selectedFilter == "Tous"
        ? favorites
        : favorites.where((f) => f["frequency"] == selectedFilter).toList();

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.gold),
          onPressed: () => context.go('/home'),
        ),
        title: const Text(
          "Mes favoris",
          style: TextStyle(
            color: AppColors.gold,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: DropdownButton<String>(
              value: selectedFilter,
              isExpanded: true,
              dropdownColor: Colors.grey[900],
              iconEnabledColor: AppColors.gold,
              style: const TextStyle(color: Colors.white, fontFamily: 'PlayfairDisplay'),
              items: ["Tous", "Quotidienne", "Hebdomadaire", "Mensuelle", "Ponctuelle"]
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedFilter = value);
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filteredFavorites.isEmpty
                ? const Center(
                    child: Text(
                      "Aucun favori enregistré pour le moment.",
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
                    itemCount: filteredFavorites.length,
                    itemBuilder: (context, index) {
                      final fav = filteredFavorites[index];
                      return FadeInLeft(
                        delay: Duration(milliseconds: 100 * index),
                        child: _favoriteCard(
                          context: context,
                          from: fav["from"]!,
                          to: fav["to"]!,
                          frequency: fav["frequency"]!,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _favoriteCard({
    required BuildContext context,
    required String from,
    required String to,
    required String frequency,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_border, color: AppColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$from ➜ $to",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 18),
                onPressed: () {
                  context.go('/results?from=$from&to=$to');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Fréquence : $frequency",
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
