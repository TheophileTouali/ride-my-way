import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import '../themes/app_theme.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}



class _ReservationsScreenState extends State<ReservationsScreen> {
  String _filter = 'À venir';

  Future<void> _addToFavorites({
  required String from,
  required String to,
  required String frequency,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Évite les doublons exacts
  final existing = await FirebaseFirestore.instance
      .collection('favorites')
      .where('userId', isEqualTo: user.uid)
      .where('from', isEqualTo: from)
      .where('to', isEqualTo: to)
      .get();

  if (existing.docs.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Ce trajet est déjà dans vos favoris"),
        backgroundColor: Colors.orangeAccent,
      ),
    );
    return;
  }

  try {
    await FirebaseFirestore.instance.collection('favorites').add({
      'userId': user.uid,
      'from': from,
      'to': to,
      'frequency': frequency,
      'createdAt': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Trajet ajouté à vos favoris"),
        backgroundColor: AppColors.gold,
      ),
    );
  } catch (e) {
    print("Erreur lors de l'ajout aux favoris : $e");
  }
}


  Stream<QuerySnapshot> _reservationsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
  }

  List<QueryDocumentSnapshot> _filterReservations(List<QueryDocumentSnapshot> reservations) {
    final now = DateTime.now();

    return reservations.map((doc) {
      final ts = doc['timestamp'] as Timestamp;
      final date = ts.toDate();
      final status = (doc['status'] ?? '').toString();

      if (status != 'Annulée' && date.isBefore(now)) {
        FirebaseFirestore.instance.collection('reservations').doc(doc.id).update({
          'status': 'Terminée'
        });
        return null;
      }
      return doc;
    }).whereType<QueryDocumentSnapshot>().where((doc) {
      final ts = doc['timestamp'] as Timestamp;
      final date = ts.toDate();
      final status = (doc['status'] ?? '').toString();

      if (_filter == 'Tous') return true;
      if (_filter == 'À venir') return date.isAfter(now);
      return status.toLowerCase() == _filter.trim().toLowerCase();
    }).toList()
      ..sort((a, b) {
        final tsA = a['timestamp'] as Timestamp;
        final tsB = b['timestamp'] as Timestamp;
        return tsA.toDate().compareTo(tsB.toDate());
      });
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return "${date.day}/${date.month}/${date.year} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }


  Future<void> _cancelReservation(String docId) async {
    await FirebaseFirestore.instance.collection('reservations').doc(docId).update({
      'status': 'Annulée',
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Réservation annulée'), backgroundColor: Colors.redAccent),
    );
  }

  String _getFieldOrDefault(QueryDocumentSnapshot doc, String key, String fallback) {
    return doc.data().toString().contains(key) ? doc[key].toString() : fallback;
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.black,
    appBar: AppBar(
      backgroundColor: AppColors.black,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
        onPressed: () => context.go('/home'),
      ),
      title: const Text(
        "Mes réservations",
        style: TextStyle(
          color: AppColors.gold,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    body: Column(
      children: [
        const SizedBox(height: 16),
        _buildFilterChips(),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _reservationsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.gold));
              }

              if (!snapshot.hasData) {
                return const Center(child: Text("Chargement des réservations...", style: TextStyle(color: Colors.white70)));
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text("Aucune réservation trouvée.", style: TextStyle(color: Colors.white70)));
              }

              final filtered = _filterReservations(docs);
              if (filtered.isEmpty) {
                return const Center(child: Text("Aucune réservation pour ce filtre.", style: TextStyle(color: Colors.white70)));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  return FadeInLeft(
                    delay: Duration(milliseconds: index * 100),
                    child: Column(
                      children: [
                        _reservationCard(
                          docId: doc.id,
                          from: doc['from'] ?? '',
                          to: doc['to'] ?? '',
                          date: _formatDate(doc['timestamp'] as Timestamp),
                          status: doc['status'] ?? 'Confirmée',
                          price: _getFieldOrDefault(doc, 'price', 'À définir'),
                          vehicle: _getFieldOrDefault(doc, 'vehicle', 'Non assigné'),
                          driver: _getFieldOrDefault(doc, 'driverName', 'Non assigné'),
                        ),
                        const SizedBox(height: 8),
                      ],
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


  Widget _buildFilterChips() {
    final statuses = ['À venir', 'Confirmée', 'En attente', 'Annulée', 'Terminée', 'Tous' ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: statuses.map((status) {
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChoiceChip(
              label: Text(status),
              selected: _filter == status,
              selectedColor: AppColors.gold,
              backgroundColor: Colors.grey[800],
              labelStyle: TextStyle(
                color: _filter == status ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (_) => setState(() => _filter = status),
            ),
          );
        }).toList(),
      ),
    );
  }
  

  Widget _reservationCard({
    required String docId,
    required String from,
    required String to,
    required String date,
    required String status,
    required String price,
    required String vehicle,
    required String driver,
  }) {
    final Color statusColor = switch (status) {
      "Confirmée" => AppColors.gold,
      "En attente" => Colors.orangeAccent,
      "Annulée" => Colors.redAccent,
      "Terminée" => Colors.white54,
      _ => Colors.white60,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white60, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "$from ➜ $to",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text("Départ : $date", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text("Prix : $price", style: const TextStyle(color: Colors.white70)),
          Text("Véhicule : $vehicle", style: const TextStyle(color: Colors.white70)),
          Text("Conducteur : $driver", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text("Statut : $status", style: TextStyle(color: statusColor)),
                    const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (status != 'Annulée')
                TextButton.icon(
                  onPressed: () => _cancelReservation(docId),
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  label: const Text("Annuler", style: TextStyle(color: Colors.redAccent)),
                ),
              ElevatedButton.icon(
                onPressed: () => _addToFavorites(
                  from: from,
                  to: to,
                  frequency: 'Ponctuelle',
                ),
                icon: const Icon(Icons.favorite_border, color: Colors.black),
                label: const Text(
                  "Favori",
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
