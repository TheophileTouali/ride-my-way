import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../themes/app_theme.dart';

class DriverTripDetailScreen extends StatelessWidget {
  final String reservationId;

  const DriverTripDetailScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Détail de la course",
          style: TextStyle(color: Colors.white, fontFamily: 'PlayfairDisplay', fontSize: 20),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('reservations').doc(reservationId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final driverId = data['driverId'];
          final userId = data['userId'];
          final status = data['status'];
          final from = data['from'] ?? 'Adresse de départ inconnue';
          final to = data['to'] ?? 'Adresse d’arrivée inconnue';
          final price = (data['price'] is num) ? data['price'].toDouble() : 0.0;

          DateTime departureTime;
          if (data['departureTime'] != null && data['departureTime'] is Timestamp) {
            departureTime = (data['departureTime'] as Timestamp).toDate();
          } else {
            departureTime = DateTime.now();
          }

          final isCurrentDriver = currentUser != null && currentUser.uid == driverId;

          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
            builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                }

                if (userSnapshot.hasError) {
                return Center(
                    child: Text(
                    "Erreur de chargement : ${userSnapshot.error}",
                    style: const TextStyle(color: Colors.redAccent),
                    ),
                );
                }

                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                return const Center(
                    child: Text(
                    "Passager introuvable",
                    style: TextStyle(color: Colors.white70),
                    ),
                );
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final firstName = userData['firstName'] ?? '';
                final lastName = userData['lastName'] ?? '';
                final passengerName = "$firstName $lastName".trim();

                return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Colors.grey.shade900, Colors.grey.shade800],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1),
                        boxShadow: [
                            BoxShadow(
                            color: AppColors.gold.withOpacity(0.15),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                            ),
                        ],
                        ),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                            passengerName,
                            style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'PlayfairDisplay',
                            ),
                            ),
                            const SizedBox(height: 18),
                            _infoRow(Icons.location_on, "Départ : $from"),
                            const SizedBox(height: 12),
                            _infoRow(Icons.flag, "Arrivée : $to"),
                            const SizedBox(height: 12),
                            _infoRow(Icons.access_time, "Départ prévu : ${DateFormat.yMMMMd('fr_FR').add_Hm().format(departureTime)}"),
                            const SizedBox(height: 12),
                            _infoRow(Icons.euro, "Prix : ${price.toStringAsFixed(2)} €"),
                            const SizedBox(height: 12),
                            _infoRow(Icons.info_outline, "Statut : $status"),
                        ],
                        ),
                    ),

                    const SizedBox(height: 30),

                    if (isCurrentDriver && status == 'Confirmée')
                        ElevatedButton.icon(
                        onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('reservations')
                                .doc(reservationId)
                                .update({'status': 'En cours'});

                            if (context.mounted) {
                            context.go('/driver/live_tracking/$reservationId');
                            }
                        },
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                        label: const Text(
                            "Commencer la course",
                            style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'PlayfairDisplay',
                            ),
                        ),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            textStyle: const TextStyle(fontSize: 16),
                        ),
                        ),
                    ],
                ),
                );
            },
            );

        },
      ),
    );
  }

  static Widget _infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.gold, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontFamily: 'Montserrat',
            ),
          ),
        ),
      ],
    );
  }
}
