import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';
import 'package:ride_my_way/utils/location_utils.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/payment_service.dart';
import 'package:flutter/foundation.dart'; // ✅ kIsWeb
import 'package:url_launcher/url_launcher.dart'; // ✅ launchUrl & LaunchMode

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

  String formatDateTime(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year} à ${dt.hour}h${dt.minute.toString().padLeft(2, '0')}";
  }

  void _selectAnotherTime() async {
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
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold,
            ),
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate != null) {
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
              style: TextButton.styleFrom(
                foregroundColor: AppColors.gold,
              ),
            ),
          ),
          child: child!,
        ),
      );

      if (pickedTime != null) {
        final selected = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() {
          _selectedDateTime = selected;
          _isNowSelected = false;
        });
      }
    }
  }

  Future<void> _confirmTrip() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Utilisateur non connecté")),
      );
      return;
    }

    try {
      // ✅ heure de départ prévue
      final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
      final departureTime =
          _isNowSelected ? nowPlus3 : (_selectedDateTime ?? nowPlus3);

      // ✅ géocode le départ (utilisé côté mobile pour lister aux conducteurs)
      final coords = await getCoordinatesFromAddress(widget.from);
      if (coords == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible de géolocaliser l'adresse.")),
        );
        return;
      }

      final currentBaseUrl = Uri.base.origin;
      debugPrint("🔎 Base URL: $currentBaseUrl");
      debugPrint("🔎 Plateforme détectée: ${kIsWeb ? 'web' : 'mobile'}");

      // ✅ Montant en CENTIMES (entier) pour Stripe
      final amountCents = (widget.price * 100).round();

      // ✅ cible explicitement la région europe-west1
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final callable = functions.httpsCallable('createPaymentIntent');

      // ✅ N’envoie baseUrl + timestamp que sur web
      final payload = <String, dynamic>{
        'amount': amountCents, // int (cents)
        'currency': 'eur',
        'from': widget.from,
        'to': widget.to,
        'vehicle': widget.vehicle,
        'distance': widget.distance,
        if (kIsWeb) ...{
          'baseUrl': currentBaseUrl,
          'timestamp': departureTime.toIso8601String(), // ✅ clé du fix “course terminée”
        },
      };

      debugPrint("📤 Données envoyées à Cloud Function: $payload");

      final result = await callable.call(payload);
      debugPrint("📥 Réponse Cloud Function: ${result.data}");

      if (kIsWeb) {
        // 🌐 Stripe Checkout (la création Firestore se fera dans PaymentSuccessScreen)
        final checkoutUrl = (result.data as Map)['checkoutUrl'] as String?;
        debugPrint("🌐 Checkout URL reçue: $checkoutUrl");

        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          final uri = Uri.parse(checkoutUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          } else {
            debugPrint("❌ Impossible d'ouvrir l'URL Stripe");
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Impossible d'ouvrir Stripe Checkout")),
            );
            return;
          }
        } else {
          debugPrint("❌ URL Stripe Checkout non fournie !");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("URL Stripe Checkout non fournie.")),
          );
          return;
        }
      } else {
        // 📱 Paiement mobile → PaymentSheet
        debugPrint("📱 Paiement mobile → ouverture PaymentSheet");
        await PaymentService.processPayment(
          stripeResponse: result.data as Map<String, dynamic>,
        );

        // ✅ Sauvegarde Firestore après succès PaymentSheet (même schéma que web)
        final reservationData = {
          'from': widget.from,
          'to': widget.to,
          'vehicle': widget.vehicle,
          'price': widget.price,
          'distance': widget.distance,
          'userId': user.uid,
          'timestamp': Timestamp.fromDate(departureTime),
          'status': 'En attente',
          'paymentStatus': 'authorized',
          'paymentIntentId': (result.data as Map)['paymentIntentId'],
          'createdAt': FieldValue.serverTimestamp(),
          'expiredSearch': false,
          'fromLat': coords.lat,
          'fromLng': coords.lng,
          'platform': 'mobile',
        };

        debugPrint("📝 Données enregistrées Firestore: $reservationData");

        final docRef = await FirebaseFirestore.instance
            .collection('reservations')
            .add(reservationData);

        debugPrint("✅ Réservation enregistrée avec ID: ${docRef.id}");
        context.go('/searching?reservationId=${docRef.id}');
      }
    } on StripeException catch (e) {
      final msg = e.error.localizedMessage ?? e.toString();
      debugPrint("❌ StripeException: $msg");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('Canceled') ? "Paiement annulé." : "Paiement annulé ou échoué.",
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Erreur paiement ou Firestore : $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Paiement annulé ou échoué.")),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            "$label : ",
            style: const TextStyle(
              color: Colors.white70,
              fontFamily: 'PlayfairDisplay',
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowBlock() {
    if (!_isNowSelected) return const SizedBox.shrink();

    final nowPlus3 = DateTime.now().add(const Duration(minutes: 3));
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Text(
            "Vous partez maintenant : ",
            style: TextStyle(
              color: Colors.white70,
              fontFamily: 'PlayfairDisplay',
              fontSize: 16,
            ),
          ),
          Expanded(
            child: Text(
              formatDateTime(nowPlus3),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Planifier votre départ",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              TextButton(
                onPressed: () async {
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
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.gold,
                          ),
                        ),
                      ),
                      child: child!,
                    ),
                  );

                  if (pickedDate != null) {
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
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.gold,
                            ),
                          ),
                        ),
                        child: child!,
                      ),
                    );

                    if (pickedTime != null) {
                      final selected = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );

                      setState(() {
                        _selectedDateTime = selected;
                        _isNowSelected = false;
                      });
                    }
                  }
                },
                child: const Text(
                  "Planifier un autre moment",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.calendar_today, color: AppColors.gold),
            ],
          ),
        ),
      ],
    );
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
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/results');
            }
          },
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                      ).createShader(bounds);
                    },
                    child: const Text(
                      "Résumé de votre trajet, conçu pour l'excellence",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'PlayfairDisplay',
                        color: Colors.white, // requis pour shader
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Résumé du trajet
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

            // Planification
            const SizedBox(height: 20),
            const Text("Planifier votre départ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay')),
            const SizedBox(height: 6),
            const Text("Vous préférez plus tard ? Choisissez le moment idéal.", style: TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'PlayfairDisplay', fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.gold.withOpacity(0.2)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), offset: Offset(0, 2), blurRadius: 6)],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                leading: const Icon(Icons.calendar_today_rounded, color: AppColors.gold),
                title: const Text("Planifier un autre moment", style: TextStyle(color: AppColors.gold, fontSize: 16, fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w600)),
                onTap: _selectAnotherTime,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tileColor: Colors.transparent,
              ),
            ),

            const Spacer(),

            // Bouton confirmation
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmTrip,
                icon: const Icon(Icons.check_circle, color: Colors.black),
                label: const Text(
                  "Confirmer ce trajet",
                  style: TextStyle(
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
