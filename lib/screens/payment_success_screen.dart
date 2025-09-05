import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:ride_my_way/utils/location_utils.dart'; // ✅ géocodage
import '../themes/app_theme.dart';

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _loading = true;

  // ✅ europe-west1
  static const String VERIFY_ENDPOINT =
      "https://europe-west1-ride-my-way-7f258.cloudfunctions.net/verifyPaymentIntent";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePaymentSuccess());
  }

  Future<void> _handlePaymentSuccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _fail("Utilisateur non connecté.");
      return;
    }

    try {
      final qp = GoRouterState.of(context).uri.queryParameters;

      final sessionId = qp['session_id'] ?? '';
      final piFromUrl = qp['payment_intent'] ?? '';

      if (sessionId.isEmpty && piFromUrl.isEmpty) {
        throw Exception(
          "Identifiant de paiement manquant (session_id / payment_intent).",
        );
      }

      // 🔎 Vérif côté serveur (timeout)
      final verifyUri = sessionId.isNotEmpty
          ? Uri.parse("$VERIFY_ENDPOINT?session_id=$sessionId")
          : Uri.parse("$VERIFY_ENDPOINT?pi=$piFromUrl");

      if (kDebugMode) debugPrint("🔎 Verify URL: $verifyUri");

      final resp =
          await http.get(verifyUri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw Exception("Vérification Stripe échouée (${resp.statusCode}).");
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final paymentStatus = (data['status'] as String?) ?? '';
      final paymentIntentId = (data['id'] as String?) ?? piFromUrl;

      if (paymentIntentId.isEmpty) {
        throw Exception("PaymentIntent introuvable.");
      }

      if (paymentStatus != 'requires_capture' && paymentStatus != 'succeeded') {
        throw Exception("Paiement non autorisé (status=$paymentStatus).");
      }

      // ✅ Infos trajet (horodatage = heure de départ prévue envoyée depuis ConfirmationScreen)
      final from = qp['from'] ?? '';
      final to = qp['to'] ?? '';
      final vehicle = qp['vehicle'] ?? '';
      final price = double.tryParse(qp['price'] ?? '0') ?? 0;
      final distance = double.tryParse(qp['distance'] ?? '0') ?? 0;
      final timestamp =
          DateTime.tryParse(qp['timestamp'] ?? '') ?? DateTime.now();

      // 🌍 Géocodage départ/arrivée (pour affichage côté chauffeur)
      final results = await Future.wait([
        getCoordinatesFromAddress(from),
        getCoordinatesFromAddress(to),
      ]);

      final coordsFrom = results[0];
      final coordsTo = results[1];

      final double? fromLat = coordsFrom?.lat;
      final double? fromLng = coordsFrom?.lng;
      final double? toLat = coordsTo?.lat;
      final double? toLng = coordsTo?.lng;

      if (fromLat == null || fromLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Adresse de départ non géolocalisée. La course pourrait ne pas apparaître côté conducteur.",
              ),
            ),
          );
        }
      }

      // 🔥 Enregistrement Firestore – schéma identique au mobile
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
        'fromLat': fromLat,
        'fromLng': fromLng,
        'toLat': toLat,
        'toLng': toLng,
        'platform': 'web',
        'source': 'checkout',
      });

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      _fail("Erreur d'enregistrement du trajet. ${e.toString()}");
    }
  }

  void _fail(String msg) {
    if (kDebugMode) debugPrint("❌ PaymentSuccess error: $msg");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    setState(() => _loading = false);
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
                  const Icon(Icons.check_circle, color: AppColors.gold, size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    "Paiement autorisé !",
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
                  ),
                ],
              ),
      ),
    );
  }
}
