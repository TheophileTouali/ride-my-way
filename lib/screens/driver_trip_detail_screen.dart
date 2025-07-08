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
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => context.go('/driver-home'),
      ),
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

          DateTime departureTime = data['departureTime'] != null && data['departureTime'] is Timestamp
              ? (data['departureTime'] as Timestamp).toDate()
              : DateTime.now();

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
                final prefs = userData['preferences'] as Map<String, dynamic>?; // ✅ corriger ici
                print("Préférences passager : $prefs");



              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // === Détails du trajet ===
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
                          const SizedBox(height: 6), //
                          const SizedBox(height: 18),
                          _infoRow(Icons.location_on, "Départ : $from"),
                          const SizedBox(height: 12),
                          _infoRow(Icons.flag, "Arrivée : $to"),
                          const SizedBox(height: 12),
                          _infoRow(Icons.access_time,
                              "Départ prévu : ${DateFormat.yMMMMd('fr_FR').add_Hm().format(departureTime)}"),
                          const SizedBox(height: 12),
                          _infoRow(Icons.euro, "Prix : ${price.toStringAsFixed(2)} €"),
                          const SizedBox(height: 12),
                          _infoRow(Icons.info_outline, "Statut : ${_getStatusLabel(status)}"),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // === Infos passager ===
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundImage: userData['photoUrl'] != null
                                    ? NetworkImage(userData['photoUrl'])
                                    : const AssetImage('assets/images/avatar_placeholder.png') as ImageProvider,
                                backgroundColor: Colors.transparent,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      passengerName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: AppColors.gold,
                                        fontFamily: 'PlayfairDisplay',
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (userData['identityCardUrl'] != null)
                                      Row(
                                        children: const [
                                          Icon(Icons.verified, color: Colors.greenAccent, size: 16),
                                          SizedBox(width: 4),
                                          Text("Identité vérifiée", style: TextStyle(color: Colors.white70)),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (status == 'En cours') ...[
                            _infoRow(Icons.phone, "Tél : ${userData['phone'] ?? 'Non renseigné'}"),
                            const SizedBox(height: 12),
                            _infoRow(Icons.email, "Email : ${userData['email'] ?? 'Non renseigné'}"),
                          ] else ...[
                            const Text(
                              "Les coordonnées seront accessibles une fois la course commencée.",
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // === Préférences passager ===
                    if (prefs != null) ...[
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Préférences du passager",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                                fontFamily: 'PlayfairDisplay',
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (prefs['music'] == true) _preferenceBadge("Musique"),
                                if (prefs['temperature'] == true) _preferenceBadge("Température personnalisée"),
                                if (prefs['wifi'] == true) _preferenceBadge("Wifi demandé"),
                                if (prefs['pets'] == true) _preferenceBadge("Accepte les animaux"),
                                if (prefs['smokeFree'] == true) _preferenceBadge("Non-fumeur"),
                                if (prefs['perfume'] == true) _preferenceBadge("Parfum apprécié"),
                                if (prefs['ambiance'] != null && prefs['ambiance'] != '')
                                  _preferenceBadge("Ambiance : ${prefs['ambiance']}"),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 30),

                    // === Bouton commencer ===
                    if (isCurrentDriver && status == 'Confirmée')


                      Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 1.0, end: 1.05),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        onEnd: () => Future.delayed(const Duration(seconds: 15)).then(
                          (_) => (context as Element).markNeedsBuild(),
                        ),
                        builder: (context, scale, child) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withOpacity(0.6), // 🌟 halo
                                  blurRadius: 20 * (scale - 1),           // pulsation
                                  spreadRadius: 1.5 * (scale - 1),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: Transform.scale(
                              scale: scale,
                              child: child,
                            ),
                          );
                        },



                        child: ElevatedButton(
  onPressed: () async {
    try {
      await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .update({
        'status': 'En cours',
        'startTime': FieldValue.serverTimestamp(),
      });

      print("➡️ Redirection vers /driver/live_tracking/$reservationId");

      if (context.mounted) {
        GoRouter.of(context).go('/driver/live_tracking/$reservationId');
      }
    } catch (e) {
      print("❌ Erreur lors de la mise à jour ou navigation : $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors du démarrage de la course."),
          ),
        );
      }
    }
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.gold,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
    textStyle: const TextStyle(fontSize: 16),
    elevation: 8,
    shadowColor: AppColors.gold,
  ),
  child: const Text(
    "Commencer la course",
    style: TextStyle(
      color: Colors.black,
      fontWeight: FontWeight.bold,
      fontFamily: 'PlayfairDisplay',
    ),
  ),
),






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

  static Widget _preferenceBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.gold.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontFamily: 'Montserrat',
        ),
      ),
    );
  }

  static String _getStatusLabel(String status) {
    switch (status) {
      case 'Confirmée':
        return 'Confirmée';
      case 'En cours':
        return 'Course en cours';
      case 'Terminée':
        return 'Course terminée';
      case 'Annulée':
        return 'Course annulée';
      default:
        return status;
    }
  }
}
