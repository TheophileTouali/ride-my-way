import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveReservation();
    });
  }

  Future<void> _saveReservation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // ✅ Utilisation correcte de GoRouterState pour extraire les query params
      final queryParams = GoRouterState.of(context).uri.queryParameters;

      final from = queryParams['from'] ?? '';
      final to = queryParams['to'] ?? '';
      final vehicle = queryParams['vehicle'] ?? '';
      final price = double.tryParse(queryParams['price'] ?? '0') ?? 0;
      final distance = double.tryParse(queryParams['distance'] ?? '0') ?? 0;
      final paymentIntentId = queryParams['payment_intent'] ?? '';
      final timestamp =
          DateTime.tryParse(queryParams['timestamp'] ?? '') ?? DateTime.now();

      await FirebaseFirestore.instance.collection('reservations').add({
        'from': from,
        'to': to,
        'vehicle': vehicle,
        'price': price,
        'distance': distance,
        'userId': user.uid,
        'timestamp': Timestamp.fromDate(timestamp),
        'status': 'En attente',
        'paymentStatus': 'authorized',
        'paymentIntentId': paymentIntentId,
        'createdAt': FieldValue.serverTimestamp(),
        'expiredSearch': false,
      });

      setState(() => _loading = false);
    } catch (e) {
      debugPrint("Erreur enregistrement Firestore Web: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur d'enregistrement du trajet.")),
        );
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: AppColors.gold)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.gold, size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    "Paiement réussi !",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/reservations'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                    ),
                    child: const Text(
                      "Voir mes réservations",
                      style: TextStyle(color: Colors.black),
                    ),
                  )
                ],
              ),
      ),
    );
  }
}
