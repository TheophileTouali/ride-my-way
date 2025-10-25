import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'package:ride_my_way/utils/location_utils.dart';
import '../themes/app_theme.dart';

class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({super.key});

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen> {
  bool _loading = true;

  // Données pour le résumé premium
  String _from = '';
  String _to = '';
  double _price = 0;
  double _distance = 0;

  static const String VERIFY_ENDPOINT =
      "https://europe-west1-ride-my-way-7f258.cloudfunctions.net/verifyPaymentIntent";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _handlePaymentSuccess());
  }

  Future<void> _shareTrip() async {
    final txt = StringBuffer()
      ..writeln("🎉 Paiement autorisé sur Ride My Way")
      ..writeln("Trajet : $_from → $_to")
      ..writeln("Distance : ${_distance.toStringAsFixed(1)} km")
      ..writeln(
          "Montant bloqué : ${_price.toStringAsFixed(2).replaceAll('.', ',')} €");
    await Share.share(txt.toString());
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
            "Identifiant de paiement manquant (session_id / payment_intent).");
      }

      final verifyUri = sessionId.isNotEmpty
          ? Uri.parse("$VERIFY_ENDPOINT?session_id=$sessionId")
          : Uri.parse("$VERIFY_ENDPOINT?pi=$piFromUrl");

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

      // Infos UI + Firestore
      _from = (qp['from'] ?? '').trim();
      _to = (qp['to'] ?? '').trim();
      _price = double.tryParse(qp['price'] ?? '0') ?? 0;
      _distance = double.tryParse(qp['distance'] ?? '0') ?? 0;
      final timestamp =
          DateTime.tryParse(qp['timestamp'] ?? '') ?? DateTime.now();

      final results = await Future.wait([
        getCoordinatesFromAddress(_from),
        getCoordinatesFromAddress(_to),
      ]);
      final coordsFrom = results[0];
      final coordsTo = results[1];

      await FirebaseFirestore.instance.collection('reservations').add({
        'from': _from,
        'to': _to,
        'vehicle': (qp['vehicle'] ?? '').trim(),
        'price': _price,
        'distance': _distance,
        'userId': user.uid,
        'timestamp': Timestamp.fromDate(timestamp),
        'status': 'En attente',
        'paymentStatus': 'authorized',
        'paymentIntentId': paymentIntentId,
        'createdAt': FieldValue.serverTimestamp(),
        'expiredSearch': false,
        'fromLat': coordsFrom?.lat,
        'fromLng': coordsFrom?.lng,
        'toLat': coordsTo?.lat,
        'toLng': coordsTo?.lng,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    setState(() => _loading = false);
  }

  String _formatPrice(double v) =>
      "${v.toStringAsFixed(2).replaceAll('.', ',')} €";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Stack(
          children: [
            const _RoyalVignette(), // halo premium
            _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : LayoutBuilder(
                    builder: (context, c) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: c.maxHeight - 52),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Center(child: const _SuccessMedallion()),
                              const SizedBox(height: 18),
                              const _RoyalTitle("Paiement autorisé !"),
                              const SizedBox(height: 4),
                              const _RoyalSubtitle(
                                  "Votre réservation est confirmée et prête."),
                              const SizedBox(height: 16),
                              const _GoldShimmerLine(),
                              const SizedBox(height: 18),

                              _SummaryCard(
                                from: _from,
                                to: _to,
                                distancePill: DistancePill(
                                    "${_distance.toStringAsFixed(1)} km"),
                                pricePill: PricePill(_formatPrice(_price)),
                              ),

                              const SizedBox(height: 26),

                              // CTA principal
                              SizedBox(
                                height: 54,
                                child: ElevatedButton.icon(
                                  onPressed: () => context.go('/reservations'),
                                  icon: const Icon(Icons.check_circle,
                                      color: Colors.black),
                                  label: const Text(
                                    "Voir mes réservations",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'PlayfairDisplay',
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      color: Colors.black,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.gold,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // CTA secondaire
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _shareTrip,
                                  icon: const Icon(Icons.ios_share_rounded,
                                      color: AppColors.gold),
                                  label: const Text(
                                    "Partager mon trajet",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontFamily: 'PlayfairDisplay',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                        color: AppColors.gold.withOpacity(.65),
                                        width: 1.2),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(18)),
                                    foregroundColor: AppColors.gold,
                                    backgroundColor: const Color(0xFF121212),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () => context.go('/home'),
                                child: const Text(
                                  "Retour à l’accueil",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontFamily: 'PlayfairDisplay',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

/* ======================= WIDGETS LUXE ======================= */

class _RoyalVignette extends StatelessWidget {
  const _RoyalVignette();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.75, -0.9),
              radius: 1.2,
              colors: [
                AppColors.gold.withOpacity(.06),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoyalTitle extends StatelessWidget {
  const _RoyalTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
      ).createShader(r),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
          height: 1.1,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _RoyalSubtitle extends StatelessWidget {
  const _RoyalSubtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white.withOpacity(.78),
        fontFamily: 'PlayfairDisplay',
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
  }
}

class _GoldShimmerLine extends StatefulWidget {
  const _GoldShimmerLine();
  @override
  State<_GoldShimmerLine> createState() => _GoldShimmerLineState();
}

class _GoldShimmerLineState extends State<_GoldShimmerLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final sweep = _c.value;
        return SizedBox(
          height: 6,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5A4A0A), Color(0xFF8C6D14)],
                  ),
                ),
              ),
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: 0.28,
                  alignment: Alignment(-1 + 2 * sweep, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x00FFE38A),
                          Color(0xFFFFD700),
                          Color(0x00FFE38A),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(.35),
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SuccessMedallion extends StatelessWidget {
  const _SuccessMedallion();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // halo doux
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.18),
                blurRadius: 36,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        // anneau externe
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: AppColors.gold.withOpacity(.22), width: 1),
          ),
        ),
        // médaille
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: Icon(Icons.check_rounded, size: 42, color: Colors.black),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String from;
  final String to;
  final Widget distancePill;
  final Widget pricePill;

  const _SummaryCard({
    required this.from,
    required this.to,
    required this.distancePill,
    required this.pricePill,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withOpacity(0.16), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.40),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
          // faux inner shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(color: AppColors.gold, width: 1.2),
                ),
                child: const Icon(Icons.route_rounded,
                    size: 18, color: AppColors.gold),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _GoldText(
                  "Résumé du trajet",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                distancePill,
                const SizedBox(width: 8),
                pricePill,
              ]),
            ],
          ),
          const SizedBox(height: 16),
          _Timeline(from: from, to: to),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final String from;
  final String to;
  const _Timeline({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppColors.gold.withOpacity(.90),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: .2,
    );
    const valueStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      height: 1.20,
      fontFamily: 'PlayfairDisplay',
      fontWeight: FontWeight.w700,
      overflow: TextOverflow.ellipsis,
    );

    Widget dot() => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
            ),
            border: Border.all(color: Color(0xFFFFEAB0), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          dot(),
          Container(
            width: 2,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              ),
            ),
          ),
          dot(),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Départ', style: labelStyle),
              const SizedBox(height: 3),
              Text(from, maxLines: 1, style: valueStyle),
              const SizedBox(height: 10),
              Text('Arrivée', style: labelStyle),
              const SizedBox(height: 3),
              Text(to, maxLines: 1, style: valueStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoldText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _GoldText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) =>
          const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFA87C00)])
              .createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/* ===== Pilules compactes (compat mobile) ===== */

class DistancePill extends StatelessWidget {
  final String text;
  const DistancePill(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
              color: AppColors.gold.withOpacity(0.10),
              blurRadius: 12,
              offset: Offset(0, 4)),
        ],
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w800,
          color: AppColors.gold,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}

class PricePill extends StatelessWidget {
  final String value;
  const PricePill(this.value, {super.key});

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
              color: AppColors.gold.withOpacity(0.22),
              blurRadius: 16,
              offset: Offset(0, 6)),
        ],
      ),
      child: Text(
        value,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          fontFamily: 'PlayfairDisplay',
          shadows: [Shadow(color: Colors.white24, blurRadius: .5)],
        ),
      ),
    );
  }
}
