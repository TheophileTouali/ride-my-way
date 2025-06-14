import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';


class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({super.key});

  final List<Map<String, String>> upcomingReservations = const [
    {
      "from": "Boissy St Léger",
      "to": "Paris",
      "date": "31 mai à 19h45",
      "status": "Confirmée"
    },
    {
      "from": "Créteil",
      "to": "La Défense",
      "date": "2 juin à 08h30",
      "status": "En attente"
    },
  ];

  final List<Map<String, String>> pastReservations = const [
    {
      "from": "Paris",
      "to": "Créteil",
      "date": "24 mai à 18h00",
      "status": "Terminée"
    },
    {
      "from": "Lyon",
      "to": "Paris",
      "date": "18 mai à 15h30",
      "status": "Annulée"
    },
  ];

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("À venir",
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'PlayfairDisplay',
                )),
            const SizedBox(height: 12),
            ...upcomingReservations.map((res) => _reservationCard(
                  context,
                  from: res["from"]!,
                  to: res["to"]!,
                  date: res["date"]!,
                  status: res["status"]!,
                )),

            const SizedBox(height: 28),

            const Text("Historique",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'PlayfairDisplay',
                )),
            const SizedBox(height: 12),
            ...pastReservations.map((res) => _reservationCard(
                  context,
                  from: res["from"]!,
                  to: res["to"]!,
                  date: res["date"]!,
                  status: res["status"]!,
                  faded: true,
                )),
          ],
        ),
      ),
    );
  }

  Widget _reservationCard(
    BuildContext context, {
    required String from,
    required String to,
    required String date,
    required String status,
    bool faded = false,
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
        color: faded ? Colors.grey[850] : Colors.grey[900],
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
          Text("Statut : $status", style: TextStyle(color: statusColor)),
        ],
      ),
    );
  }
}
