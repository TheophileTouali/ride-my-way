import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  Stream<QuerySnapshot> _favoritesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    final baseQuery = FirebaseFirestore.instance
        .collection('favorites')
        .where('userId', isEqualTo: user.uid);

    if (selectedFilter != "Tous") {
      return baseQuery.where('frequency', isEqualTo: selectedFilter).snapshots();
    }

    return baseQuery.snapshots();
  }

  Future<void> _confirmDeleteFavorite(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Supprimer ce favori ?',
          style: TextStyle(color: Colors.white, fontFamily: 'PlayfairDisplay'),
        ),
        content: const Text(
          'Êtes-vous sûr de vouloir supprimer ce trajet de vos favoris ?',
          style: TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance.collection('favorites').doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Favori supprimé."), backgroundColor: AppColors.gold),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: StreamBuilder<QuerySnapshot>(
              stream: _favoritesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Aucun favori trouvé.",
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final from = doc['from'] ?? '';
                    final to = doc['to'] ?? '';
                    final frequency = doc['frequency'] ?? '';

                    return FadeInLeft(
                      delay: Duration(milliseconds: 100 * index),
                      child: _favoriteCard(
                        context: context,
                        from: from,
                        to: to,
                        frequency: frequency,
                        docId: doc.id,
                      ),
                    );
                  },
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
    required String docId,
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
              const Icon(Icons.favorite, color: AppColors.gold, size: 20),
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
                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                onPressed: () => _confirmDeleteFavorite(docId),
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
