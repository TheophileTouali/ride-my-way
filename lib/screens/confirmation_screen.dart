import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart'; // StripeException
import 'package:url_launcher/url_launcher.dart';

import '../services/payment_service.dart';
import '../themes/app_theme.dart';
import 'package:ride_my_way/utils/location_utils.dart';

class ConfirmationScreen extends StatefulWidget {
  final String from;
  final String to;
  final String vehicle;
  final double price;
  final double distance;

  const ConfirmationScreen({
    super.key,
    required this.from,
    required this.to,
    required this.vehicle,
    required this.price,
    required this.distance,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  DateTime? _selectedDateTime;
  bool _isNowSelected = true;
  bool _loading = false;

  String formatDateTime(DateTime dt) =>
      "${dt.day}/${dt.month}/${dt.year} à ${dt.hour}h${dt.minute.toString().padLeft(2, '0')}";

  Future<void> _selectAnotherTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0D0D0D),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF0D0D0D),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
          ),
        ),
        child: child!,
      ),
    );

    if (pickedTime == null) return;

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _isNowSelected = false;
    });
  }

  Future<void> _confirmTrip() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Utilisateur non connecté.")),
      );
      return;
    }

    if (_loading) return;
    setState(() => _loading = true);

    final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
    final departureTime = _isNowSelected ? nowPlus3 : (_selectedDateTime ?? nowPlus3);

    try {
      // 1) Géocodage départ (obligatoire pour la recherche conducteur)
      final coords = await getCoordinatesFromAddress(widget.from);
      if (coords == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de géolocaliser l'adresse.")),
        );
        return;
      }

      // 2) Crée le PaymentIntent (centimes)
      final amountCents = (widget.price * 100).round();
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('createPaymentIntent');

      final payload = <String, dynamic>{
        'amount': amountCents,
        'currency': 'eur',
        'from': widget.from,
        'to': widget.to,
        'vehicle': widget.vehicle,
        'distance': widget.distance,
        if (kIsWeb)
          ...{
            'baseUrl': Uri.base.origin,
            'timestamp': departureTime.toIso8601String(),
          }
      };

      final result = await callable.call(payload);
      final data = Map<String, dynamic>.from(result.data as Map);

      // 3) Paiement
      if (kIsWeb) {
        // --- WEB : Stripe Checkout ---
        final checkoutUrl = data['checkoutUrl'] as String?;
        if (checkoutUrl == null || checkoutUrl.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("URL Stripe Checkout non fournie.")),
          );
          return;
        }
        final ok = await launchUrl(
          Uri.parse(checkoutUrl),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Impossible d'ouvrir Stripe Checkout.")),
          );
        }
        return; // la création Firestore se fait sur l’écran de succès web
      } else {
        // --- MOBILE : PaymentSheet ---
        await PaymentService.processPayment(stripeResponse: data);

        // 4) Enregistre la réservation SEULEMENT si PaymentSheet validée
        final reservation = {
          'from': widget.from,
          'to': widget.to,
          'vehicle': widget.vehicle,
          'price': widget.price,
          'distance': widget.distance,
          'userId': user.uid,
          'timestamp': Timestamp.fromDate(departureTime),
          'status': 'En attente',
          'paymentStatus': 'authorized',
          'paymentIntentId': data['paymentIntentId'],
          'createdAt': FieldValue.serverTimestamp(),
          'expiredSearch': false,
          'fromLat': coords.lat,
          'fromLng': coords.lng,
          'platform': 'mobile',
        };

        final docRef = await FirebaseFirestore.instance
            .collection('reservations')
            .add(reservation);

        context.go('/searching?reservationId=${docRef.id}');
      }
    }

    // --- Erreurs Cloud Functions (auth, montant invalide, etc.) ---
    on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur serveur paiement : $msg')),
      );
    }

    // --- Erreurs Stripe : on détecte l'annulation sans l'enum (compatible toutes versions) ---
    on StripeException catch (e) {
      final codeStr = e.error.code.toString().toLowerCase(); // ex: "failurecode.canceled"
      final isCanceled = codeStr.contains('canceled') || codeStr.contains('cancelled');
      final msg = e.error.message ?? (isCanceled ? 'Paiement annulé.' : 'Paiement refusé.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCanceled ? 'Paiement annulé par l’utilisateur.' : 'Paiement refusé : $msg')),
      );
    }

    // --- Autres erreurs (réseau, parsing, etc.) ---
    catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur inattendue : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
    final departureTime = _isNowSelected ? nowPlus3 : (_selectedDateTime ?? nowPlus3);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.gold, size: 20),
          tooltip: 'Retour',
          onPressed: () => context.canPop() ? context.pop() : context.go('/results'),
        ),
        title: const Text(
          "Confirmation de votre trajet sur mesure",
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            color: AppColors.gold,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                  ).createShader(bounds),
                  child: const Text(
                    "Résumé de votre trajet, conçu pour l'excellence",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PlayfairDisplay',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // Résumé
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gold.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoLine("Départ", widget.from),
                  const SizedBox(height: 10),
                  _buildInfoLine("Arrivée", widget.to),
                  const SizedBox(height: 10),
                  _buildInfoLine("Véhicule", widget.vehicle),
                  const SizedBox(height: 10),
                  _buildInfoLine("Distance", "${widget.distance.toStringAsFixed(1)} km"),
                  const SizedBox(height: 10),
                  _buildInfoLine("Prix", "${widget.price.toStringAsFixed(2)} €"),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Départ immédiat
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(0, 2),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_filled_rounded, color: AppColors.gold, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Vous partez maintenant : ${_formatTimestamp(Timestamp.fromDate(departureTime))}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "Planifier votre départ",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Vous préférez plus tard ? Choisissez le moment idéal.",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontFamily: 'PlayfairDisplay',
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), offset: const Offset(0, 2), blurRadius: 6),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                leading: const Icon(Icons.calendar_today_rounded, color: AppColors.gold),
                title: const Text(
                  "Planifier un autre moment",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 16,
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: _selectAnotherTime,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.transparent,
              ),
            ),

            const Spacer(),

            // Bouton
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _confirmTrip,
                icon: _loading
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check_circle, color: Colors.black),
                label: Text(
                  _loading ? "Traitement..." : "Confirmer ce trajet",
                  style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label : ",
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return "${dateTime.day}/${dateTime.month}/${dateTime.year} à ${dateTime.hour}h${dateTime.minute.toString().padLeft(2, '0')}";
  }
}
