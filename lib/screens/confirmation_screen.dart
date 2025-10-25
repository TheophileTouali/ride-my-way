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

// ⏱️ Buffer global (minutes) pour garder la course visible/urgente
const int _NOW_BUFFER_MIN = 6;

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

  ThemeData _goldPickerThemeData() {
    final base = ThemeData.dark();
    return base.copyWith(
      // Global colors
      colorScheme: const ColorScheme.dark(
        primary: AppColors.gold,
        onPrimary: Colors.black,
        surface: Color(0xFF101010),
        onSurface: Colors.white,
      ),

      // Dialog container (Date/Time pickers)
      dialogBackgroundColor: const Color(0xFF0D0D0D),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      // Buttons: OK / Annuler
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.gold,
          textStyle: const TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      // TimePicker (use simple Color fields for broad SDK compatibility)
      timePickerTheme: TimePickerThemeData(
        backgroundColor: const Color(0xFF0D0D0D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        helpTextStyle: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        hourMinuteColor:
            const Color(0xFF1A1A1A), // <-- Color, not *StateProperty
        hourMinuteTextColor: Colors.white,
        dialHandColor: AppColors.gold,
        dialBackgroundColor: const Color(0xFF1A1A1A),
      ),

      // Keep DatePicker theming minimal to avoid API diffs across SDKs
      datePickerTheme: DatePickerThemeData(
        backgroundColor: const Color(0xFF101010),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Widget _goldPickerTheme(Widget child) =>
      Theme(data: _goldPickerThemeData(), child: child);

  // ---------- Paiement / réservation : inchangé ----------
  String formatDateTime(DateTime dt) =>
      "${dt.day}/${dt.month}/${dt.year} à ${dt.hour}h${dt.minute.toString().padLeft(2, '0')}";

  Future<void> _selectAnotherTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
      helpText: 'Sélectionner une date',
      cancelText: 'Annuler',
      confirmText: 'OK',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => _goldPickerTheme(child!),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Choisissez l’heure',
      confirmText: 'Valider',
      cancelText: 'Annuler',
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => _goldPickerTheme(child!),
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
    // ---- toute ta logique existante (paiement / Firestore) INCHANGÉE ----
    // Copie/colle intégralement ta méthode actuelle ici.
    // (Je n’altère pas la partie réseau/paiement)
    // ---------------------------------------------------------------------
    // BEGIN: copie de ta version existante
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Utilisateur non connecté.")),
      );
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);

    final nowPlusBuf =
        DateTime.now().add(const Duration(minutes: _NOW_BUFFER_MIN));
    DateTime departureTime =
        _isNowSelected ? nowPlusBuf : (_selectedDateTime ?? nowPlusBuf);
    if (departureTime.isBefore(nowPlusBuf)) {
      departureTime = nowPlusBuf;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Heure ajustée à +$_NOW_BUFFER_MIN min pour garantir la prise en charge.")),
        );
      }
    }

    try {
      final coords = await getCoordinatesFromAddress(widget.from);
      if (coords == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Impossible de géolocaliser l'adresse.")),
        );
        return;
      }

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
        'planned': !_isNowSelected,
        if (kIsWeb) ...{
          'baseUrl': Uri.base.origin,
          'timestamp': departureTime.toIso8601String(),
        }
      };

      final result = await callable.call(payload);
      final data = Map<String, dynamic>.from(result.data as Map);

      if (kIsWeb) {
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
            const SnackBar(
                content: Text("Impossible d'ouvrir Stripe Checkout.")),
          );
        }
        return;
      } else {
        await PaymentService.processPayment(stripeResponse: data);

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

        if (mounted) {
          context.go('/searching?reservationId=${docRef.id}');
        }
      }
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? e.code;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur serveur paiement : $msg')),
      );
    } on StripeException catch (e) {
      final codeStr = e.error.code.toString().toLowerCase();
      final isCanceled =
          codeStr.contains('canceled') || codeStr.contains('cancelled');
      final msg = e.error.message ??
          (isCanceled ? 'Paiement annulé.' : 'Paiement refusé.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(isCanceled
                ? 'Paiement annulé par l’utilisateur.'
                : 'Paiement refusé : $msg')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur inattendue : $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // END: copie de ta version existante
  }

  // ---------- UI PREMIUM MOBILE-FIRST ----------
  @override
  Widget build(BuildContext context) {
    final nowPlusBuf =
        DateTime.now().add(const Duration(minutes: _NOW_BUFFER_MIN));
    final departureTime =
        _isNowSelected ? nowPlusBuf : (_selectedDateTime ?? nowPlusBuf);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.gold, size: 20),
          tooltip: 'Retour',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/results'),
        ),
        title: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
          ).createShader(r),
          child: const Text(
            "Confirmation de votre trajet",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(10),
          child: _RoyalDivider(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            // Ruban d'accroche premium
            Row(
              children: const [
                Icon(Icons.star_rounded, color: AppColors.gold, size: 20),
                SizedBox(width: 8),
                _GoldGradText(
                  "Prêt à voyager avec distinction",
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Carte résumé trajet + pilules
            _SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête + pilules
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          border: Border.all(color: AppColors.gold, width: 1.2),
                        ),
                        child: const Icon(Icons.route_rounded,
                            size: 16, color: AppColors.gold),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Trajet",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontFamily: 'PlayfairDisplay',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _Pill(text: "${widget.distance.toStringAsFixed(1)} km"),
                      const SizedBox(width: 8),
                      _PricePill(value: "${widget.price.toStringAsFixed(2)} €"),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Timeline départ/arrivée (anti-overflow)
                  _RoutePointsCompact(from: widget.from, to: widget.to),
                  const SizedBox(height: 12),
                  // Véhicule sélectionné
                  Row(
                    children: [
                      const Icon(Icons.directions_car_filled_rounded,
                          size: 16, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.vehicle,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'PlayfairDisplay',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Départ : maintenant vs planifié (toggle mobile-first)
            _SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _GoldGradText(
                    "Départ",
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SegmentChip(
                        label: "Maintenant",
                        selected: _isNowSelected,
                        onTap: () => setState(() => _isNowSelected = true),
                      ),
                      _SegmentChip(
                        label: "Planifier",
                        selected: !_isNowSelected,
                        onTap: () => setState(() => _isNowSelected = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.access_time_filled_rounded,
                          size: 18, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isNowSelected
                              ? "Vous partez maintenant : ${_formatTimestamp(Timestamp.fromDate(departureTime))}"
                              : "Départ planifié : ${_formatTimestamp(Timestamp.fromDate(departureTime))}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'PlayfairDisplay',
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_isNowSelected) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _selectAnotherTime,
                      icon: const Icon(Icons.calendar_today_rounded,
                          color: AppColors.gold, size: 16),
                      label: const Text(
                        "Choisir la date et l’heure",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.gold.withOpacity(.55), width: 1),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        backgroundColor: Colors.black.withOpacity(.15),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Bouton principal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _confirmTrip,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_circle, color: Colors.black),
                label: Text(
                  _loading ? "Traitement..." : "Confirmer ce trajet",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dateTime = timestamp.toDate();
    return "${dateTime.day}/${dateTime.month}/${dateTime.year} à ${dateTime.hour}h${dateTime.minute.toString().padLeft(2, '0')}";
  }
}

// -------------------- Widgets premium (mobiles & compacts) --------------------

class _RoyalDivider extends StatelessWidget {
  const _RoyalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            AppColors.gold.withOpacity(.28),
            Colors.transparent
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.80),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.45),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GoldGradText extends StatelessWidget {
  const _GoldGradText(this.text, {required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
      ).createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          color: AppColors.gold,
          fontFamily: 'PlayfairDisplay',
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.value});
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFFFE680), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}

class _RoutePointsCompact extends StatelessWidget {
  const _RoutePointsCompact({required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(
        children: [
          _dot(),
          Container(
            width: 2,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              ),
            ),
          ),
          _dot(),
        ],
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pointLine('Départ', from),
            const SizedBox(height: 6),
            _pointLine('Arrivée', to),
          ],
        ),
      ),
    ]);
  }

  Widget _dot() => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(.35),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ],
          border: Border.all(color: const Color(0xFFFFEAB0), width: 1),
        ),
      );

  Widget _pointLine(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.gold.withOpacity(.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.2,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
        ],
      );
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                )
              : null,
          color: selected ? null : Colors.black.withOpacity(.25),
          border: Border.all(
            color: selected
                ? const Color(0xFFFFE680)
                : AppColors.gold.withOpacity(.35),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(.22),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.w800,
            color: selected ? Colors.black : AppColors.gold,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}
