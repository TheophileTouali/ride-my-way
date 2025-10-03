import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../themes/app_theme.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  final Set<String> _redirectedReservationIds = {};
  String _filter = 'À venir';

  void _showPremiumFavoriteOverlay(String message) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: 80,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite, color: Colors.black, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Timer(const Duration(milliseconds: 2500), () => overlayEntry.remove());
  }

  Future<void> _addToFavorites({
    required String from,
    required String to,
    required String frequency,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final existing = await FirebaseFirestore.instance
        .collection('favorites')
        .where('userId', isEqualTo: user.uid)
        .where('from', isEqualTo: from)
        .where('to', isEqualTo: to)
        .get();

    if (existing.docs.isNotEmpty) {
      _showPremiumFavoriteOverlay("Ce trajet est déjà dans vos favoris");
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

      _showPremiumFavoriteOverlay("Trajet ajouté à vos favoris");
    } catch (e) {
      // ignore: avoid_print
      print("Erreur lors de l'ajout aux favoris : $e");
    }
  }

  Future<void> _cancelReservation(String docId) async {
    await FirebaseFirestore.instance
        .collection('reservations')
        .doc(docId)
        .update({'status': 'Annulée'});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Réservation annulée'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Stream<QuerySnapshot> _reservationsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
  }

  List<QueryDocumentSnapshot> _filterReservations(
    List<QueryDocumentSnapshot> reservations,
  ) {
    final now = DateTime.now();

    return reservations
        .map((doc) {
          final ts = doc['timestamp'] as Timestamp;
          final date = ts.toDate();
          final status = (doc['status'] ?? '').toString();

          // Si la date est passée et que ce n'est pas annulé/terminé => on termine.
          if (status != 'Annulée' && date.isBefore(now) && status != 'Terminée') {
            FirebaseFirestore.instance
                .collection('reservations')
                .doc(doc.id)
                .update({'status': 'Terminée'});
          }
          return doc;
        })
        .whereType<QueryDocumentSnapshot>()
        .where((doc) {
          final ts = doc['timestamp'] as Timestamp;
          final date = ts.toDate();
          final status = (doc['status'] ?? '').toString();

          if (_filter == 'Tous') return true;
          if (_filter == 'À venir') return date.isAfter(now);
          return status.toLowerCase() == _filter.trim().toLowerCase();
        })
        .toList()
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

  String _getFieldOrDefault(
    QueryDocumentSnapshot doc,
    String key,
    String fallback,
  ) {
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
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: Text(
                      "Chargement des réservations...",
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                // Redirection automatique vers la course active/en route
                if (_redirectedReservationIds.isEmpty) {
                  // 1) "En cours"
                  final enCoursDocs =
                      docs.where((doc) => doc['status'] == 'En cours').toList();
                  if (enCoursDocs.isNotEmpty) {
                    enCoursDocs.sort((a, b) {
                      final aTime = (a['timestamp'] as Timestamp).toDate();
                      final bTime = (b['timestamp'] as Timestamp).toDate();
                      return bTime.compareTo(aTime);
                    });
                    final latestDoc = enCoursDocs.first;
                    final id = latestDoc.id;

                    _redirectedReservationIds.add(id);
                    // ignore: avoid_print
                    print("🚀 Redirection vers /tracking/$id");
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) context.go('/tracking/$id');
                    });
                    return const SizedBox.shrink();
                  }

                  // 2) "En route"
                  final enRouteDocs =
                      docs.where((doc) => doc['status'] == 'En route').toList();
                  if (enRouteDocs.isNotEmpty) {
                    enRouteDocs.sort((a, b) {
                      final aTime = (a['timestamp'] as Timestamp).toDate();
                      final bTime = (b['timestamp'] as Timestamp).toDate();
                      return bTime.compareTo(aTime);
                    });
                    final latestDoc = enRouteDocs.first;
                    final id = latestDoc.id;

                    _redirectedReservationIds.add(id);
                    // ignore: avoid_print
                    print("🛰️ Redirection vers /tracking/$id (En route)");
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) context.go('/tracking/$id');
                    });
                    return const SizedBox.shrink();
                  }
                }

                final filtered = _filterReservations(docs);
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      "Aucune réservation pour ce filtre.",
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                            status:
                                _getFieldOrDefault(doc, 'status', 'En attente'),
                            price: _getFieldOrDefault(doc, 'price', 'À définir'),
                            vehicle: _getFieldOrDefault(
                                doc, 'vehicle', 'Non assigné'),
                            driver: _getFieldOrDefault(
                                doc, 'driverName', 'Non assigné'),
                            docSnapshot: doc,
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
    final statuses = [
      'À venir',
      'Confirmée',
      'En attente',
      'Annulée',
      'Terminée',
      'Tous'
    ];
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

  // --- UI helpers -----------------------------------------------------------

  // Petit badge arrondi
  Widget _pill(
    String text, {
    Color bg = const Color(0xFF2A2A2A),
    Color fg = Colors.white70,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
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
    required QueryDocumentSnapshot docSnapshot,
  }) {
    final Color statusColor = switch (status) {
      "Confirmée" => AppColors.gold,
      "En attente" => Colors.orangeAccent,
      "Annulée" => Colors.redAccent,
      "Terminée" => Colors.white54,
      _ => Colors.white60,
    };

    // Statut de paiement (aligné Stripe)
    // authorized => préautorisé ; succeeded => capturé/payé
    final paymentStatus = (docSnapshot.data().toString().contains('paymentStatus'))
        ? (docSnapshot['paymentStatus'] as String? ?? '')
        : '';
    final bool isAuthorized = paymentStatus == 'authorized';
    final bool isCaptured = paymentStatus == 'succeeded';

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
          Text("Véhicule : $vehicle",
              style: const TextStyle(color: Colors.white70)),
          Text("Conducteur : $driver",
              style: const TextStyle(color: Colors.white70)),

          const SizedBox(height: 10),

          // Statut + badge paiement
          Row(
            children: [
              Text("Statut : $status", style: TextStyle(color: statusColor)),
              const SizedBox(width: 10),
              if (isCaptured)
                _pill(
                  "Payé",
                  bg: Colors.green.withOpacity(0.15),
                  fg: Colors.greenAccent,
                  icon: Icons.verified_rounded,
                )
              else if (isAuthorized)
                _pill(
                  "Préautorisé",
                  bg: Colors.blueGrey.shade800,
                  fg: Colors.white70,
                  icon: Icons.lock_clock_rounded,
                ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Annuler : seulement si non terminée/annulée
              if (status != 'Annulée' && status != 'Terminée')
                TextButton.icon(
                  onPressed: () => _cancelReservation(docId),
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  label: const Text(
                    "Annuler",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),

              // (Le bouton "Payer maintenant" a été SUPPRIMÉ – capture automatique côté serveur)
              if (isCaptured)
                const Icon(Icons.verified_rounded,
                    color: Colors.greenAccent, size: 28),
            ],
          ),

          const SizedBox(height: 6),

          // Favori
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          if (status == 'Arrivé') const SizedBox(height: 6),
          if (status == 'Arrivé')
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('reservations')
                    .doc(docId)
                    .update({'status': 'En cours'});
                _showPremiumFavoriteOverlay("Trajet démarré !");
              },
              icon: const Icon(Icons.directions_car, color: Colors.black),
              label: const Text(
                "Je monte",
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

          if (status == 'En cours') const SizedBox(height: 6),
          if (status == 'En cours')
            ElevatedButton.icon(
              onPressed: () => context.go('/tracking/$docId'),
              icon: const Icon(Icons.navigation, color: Colors.black),
              label: const Text(
                "Suivre le trajet",
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
