// lib/screens/driver_trip_detail_screen.dart
import 'dart:math';
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
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.go('/driver-home'),
        ),
        title: ShaderMask(
          shaderCallback: _goldShader,
          child: const Text(
            "Détail de la course",
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'PlayfairDisplay',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
      ),

      // décor premium (vignette + halos)
      body: Stack(
        children: [
          const _VignetteBackground(),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('reservations')
                .doc(reservationId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;
              final driverId = data['driverId'];
              final userId = data['userId'];
              final status = (data['status'] ?? '').toString();
              final from =
                  (data['from'] ?? 'Adresse de départ inconnue').toString();
              final to =
                  (data['to'] ?? 'Adresse d’arrivée inconnue').toString();
              final price = (data['price'] is num)
                  ? (data['price'] as num).toDouble()
                  : 0.0;
              final departureTime = (data['departureTime'] is Timestamp)
                  ? (data['departureTime'] as Timestamp).toDate()
                  : DateTime.now();

              final isCurrentDriver = currentUser?.uid == driverId;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.gold));
                  }
                  if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                    return const Center(
                      child: Text("Passager introuvable",
                          style: TextStyle(color: Colors.white70)),
                    );
                  }

                  final userData =
                      userSnapshot.data!.data() as Map<String, dynamic>;
                  final firstName = (userData['firstName'] ?? '').toString();
                  final lastName = (userData['lastName'] ?? '').toString();
                  final passengerName = "$firstName $lastName".trim();
                  final prefs =
                      userData['preferences'] as Map<String, dynamic>?;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ───────────── TRAJET ─────────────
                        _GlassGoldCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle(
                                  icon: Icons.emoji_transportation_rounded,
                                  label: "Trajet"),
                              const SizedBox(height: 14),

                              // Timeline From → To (plus premium que 2 lignes indépendantes)
                              _TimelineRoute(from: from, to: to),

                              const SizedBox(height: 12),
                              const _GlassDivider(),

                              const SizedBox(height: 12),
                              _InfoRow(
                                  icon: Icons.schedule_rounded,
                                  text:
                                      "Départ : ${DateFormat.yMMMMd('fr_FR').add_Hm().format(departureTime)}"),
                              const SizedBox(height: 8),
                              _InfoRow(
                                  icon: Icons.euro_rounded,
                                  text: "Prix : ${price.toStringAsFixed(2)} €"),
                              const SizedBox(height: 8),
                              _InfoRow(
                                  icon: Icons.info_outline_rounded,
                                  text: "Statut : ${_statusLabel(status)}"),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        // ───────────── PASSAGER ─────────────
                        _GlassGoldCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle(
                                  icon: Icons.person_rounded,
                                  label: "Passager"),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  // Avatar + halo
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              AppColors.gold.withOpacity(.20),
                                          blurRadius: 20,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 34,
                                      backgroundImage: userData['photoUrl'] !=
                                              null
                                          ? NetworkImage(userData['photoUrl'])
                                          : const AssetImage(
                                                  'assets/images/avatar_placeholder.png')
                                              as ImageProvider,
                                      backgroundColor: Colors.black26,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ShaderMask(
                                          shaderCallback: _goldShader,
                                          child: Text(
                                            passengerName.isEmpty
                                                ? "Passager"
                                                : passengerName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'PlayfairDisplay',
                                              fontWeight: FontWeight.w800,
                                              fontSize: 20,
                                              letterSpacing: .2,
                                            ),
                                          ),
                                        ),
                                        if (userData['identityCardUrl'] != null)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4.0),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.verified_rounded,
                                                    size: 16,
                                                    color: Colors.greenAccent),
                                                SizedBox(width: 6),
                                                Text("Identité vérifiée",
                                                    style: TextStyle(
                                                        color: Colors.white70)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (status == 'En cours' ||
                                  status == 'Terminée') ...[
                                _InfoRow(
                                    icon: Icons.call_rounded,
                                    text: "Tél : ${userData['phone'] ?? '—'}"),
                                const SizedBox(height: 8),
                                _InfoRow(
                                    icon: Icons.email_rounded,
                                    text:
                                        "Email : ${userData['email'] ?? '—'}"),
                              ] else
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Text(
                                    "Les coordonnées seront visibles une fois la course commencée.",
                                    style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // ───────────── PRÉFÉRENCES ─────────────
// ─────────────────── PRÉFÉRENCES (basé sur PassengerPreferences) ───────────────────
                        if (prefs != null) ...[
                          const SizedBox(height: 22),
                          _GlassGoldCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle(
                                    icon: Icons.auto_awesome_rounded,
                                    label: "Préférences"),
                                const SizedBox(height: 12),
                                PassengerPrefsChips(prefs: prefs),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 26),

                        // ───────────── CTAS ─────────────
                        if (isCurrentDriver && status == 'Confirmée')
                          _PrimaryGlowButton(
                            icon: Icons.directions_car_filled_rounded,
                            label: "Commencer la prise en charge",
                            onTap: () async {
                              await FirebaseFirestore.instance
                                  .collection('reservations')
                                  .doc(reservationId)
                                  .update({
                                'status': 'En route',
                                'startTime': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                context.go(
                                    '/driver/pickup_tracking/$reservationId');
                              }
                            },
                          ),

                        if (isCurrentDriver && status == 'Arrivé') ...[
                          const SizedBox(height: 8),
                          const _InfoBanner(
                              "⏳ En attente que le passager confirme être à bord…"),
                        ],

                        if (isCurrentDriver && status == 'À bord') ...[
                          _PrimaryGlowButton(
                            icon: Icons.play_arrow_rounded,
                            label: "Démarrer la course",
                            glow: true,
                            onTap: () async {
                              await FirebaseFirestore.instance
                                  .collection('reservations')
                                  .doc(reservationId)
                                  .update({
                                'status': 'En cours',
                                'startTime': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                context
                                    .go('/driver/live_tracking/$reservationId');
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static Shader _goldShader(Rect r) => const LinearGradient(
        colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r);
}

/// ───────────────────────── décor ─────────────────────────

class _VignetteBackground extends StatelessWidget {
  const _VignetteBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                radius: 1.08,
                colors: [Color(0xFF0C0C0C), Color(0xFF060606)],
              ),
            ),
          ),
        ),
        Positioned(
            left: -120,
            top: -60,
            child:
                _GlowBall(color: AppColors.gold.withOpacity(.08), size: 260)),
        Positioned(
            right: -140,
            bottom: -80,
            child:
                _GlowBall(color: AppColors.gold.withOpacity(.06), size: 300)),
      ],
    );
  }
}

class _GlowBall extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowBall({required this.size, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: color, blurRadius: size * .6, spreadRadius: size * .25)
        ],
      ),
    );
  }
}

/// ───────────────────────── blocs luxe ─────────────────────────

class _GlassGoldCard extends StatelessWidget {
  final Widget child;
  const _GlassGoldCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F0F0F), Color(0xFF171717)],
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // bordure interne dorée (soft)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(.05),
                      blurRadius: 18,
                      spreadRadius: -6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r),
          child: const Text(
            " ",
            style: TextStyle(color: Colors.white),
          ),
        ),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: "PlayfairDisplay",
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: _GlassDivider(opacity: .25)),
      ],
    );
  }
}

class _GlassDivider extends StatelessWidget {
  final double opacity;
  const _GlassDivider({this.opacity = .18});
  @override
  Widget build(BuildContext context) {
    return Opacity(
        opacity: opacity, child: Container(height: 1, color: Colors.white));
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // médaillon d’icône
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, color: Colors.black, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldPill extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _GoldPill(
    this.text, {
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF141414),
            Color(0xFF0D0D0D),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.gold.withOpacity(.42)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.18),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFFFFE08A), Color(0xFFB78900)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(r),
              child: Icon(
                icon,
                size: 15,
                color: Colors.white,
              ),
            ),
          if (icon != null) const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13.6,
              letterSpacing: .25,
            ),
          ),
        ],
      ),
    );
  }
}

/// timeline chic From → To
class _TimelineRoute extends StatelessWidget {
  final String from;
  final String to;
  const _TimelineRoute({required this.from, required this.to});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // colonne timeline
        Column(
          children: [
            _dot(true),
            Container(
                width: 2, height: 22, color: Colors.white.withOpacity(.12)),
            _dot(false),
          ],
        ),
        const SizedBox(width: 12),
        // textes
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _timelineLine("Départ : $from"),
              const SizedBox(height: 8),
              _timelineLine("Arrivée : $to"),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot(bool filled) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? AppColors.gold : Colors.transparent,
          border: Border.all(color: AppColors.gold),
          boxShadow: filled
              ? [
                  BoxShadow(
                      color: AppColors.gold.withOpacity(.35), blurRadius: 10)
                ]
              : null,
        ),
      );

  Widget _timelineLine(String t) => Text(
        t,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 15.5,
          height: 1.35,
        ),
      );
}

class _PrimaryGlowButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool glow;
  final VoidCallback onTap;
  const _PrimaryGlowButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.glow = false,
  });

  @override
  State<_PrimaryGlowButton> createState() => _PrimaryGlowButtonState();
}

class _PrimaryGlowButtonState extends State<_PrimaryGlowButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final shimmer = (sin(_c.value * 2 * pi) + 1) / 2; // 0..1
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              boxShadow: widget.glow
                  ? [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(.35 + .25 * shimmer),
                        blurRadius: 28 + 8 * shimmer,
                        spreadRadius: 1.5,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(.22),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: ElevatedButton.icon(
              onPressed: widget.onTap,
              icon: Icon(widget.icon, color: Colors.black),
              label: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: .2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String msg;
  const _InfoBanner(this.msg);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.black.withOpacity(.35),
        border: Border.all(color: AppColors.gold.withOpacity(.38)),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.gold, fontSize: 14),
      ),
    );
  }
}

/// ───────────────────────── helpers ─────────────────────────

String _statusLabel(String status) {
  switch (status) {
    case 'Confirmée':
      return 'Confirmée';
    case 'À bord':
      return 'Passager à bord';
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

class PassengerPrefsChips extends StatelessWidget {
  final Map<String, dynamic> prefs;
  const PassengerPrefsChips({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    String? _s(String k) => (prefs[k]?.toString().trim().isEmpty ?? true)
        ? null
        : prefs[k].toString().trim();
    bool _b(String k) => prefs[k] == true;

    // ----- Ambiance & musique
    final ambiance = _s('ambiance'); // Silencieux, Discret, Dynamique, Libre
    if (ambiance != null) chips.add(_GoldPill('Ambiance : $ambiance'));

    final music = _b('music');
    final musicStyle = _s('musicStyle');
    if (music &&
        (ambiance != 'Silencieux') &&
        musicStyle != null &&
        musicStyle != 'Aucun') {
      chips.add(_GoldPill('Musique : $musicStyle'));
    }

    // ----- Conversation
    final conversation = _s('conversation');
    if (conversation != null)
      chips.add(_GoldPill('Conversation : $conversation'));

    // ----- Température
    if (_b('temperature')) {
      final tempLevel = _s('temperatureLevel');
      if (tempLevel != null) chips.add(_GoldPill('Température : $tempLevel'));
    }

    // ----- Parfum
    if (_b('perfume')) {
      final scentLevel = _s('scentLevel');
      if (scentLevel != null) chips.add(_GoldPill('Parfum : $scentLevel'));
    }

    // ----- Lumière d’ambiance (pas pertinente pour Moto)
    final vehicleType = _s('vehicleType');
    final ambientLight = _s('ambientLight');
    if (vehicleType != 'Moto' && ambientLight != null) {
      chips.add(_GoldPill('Lumière : $ambientLight'));
    }

    // ----- Confort / équipements
    final seatPosition = _s('seatPosition'); // Avant/Arrière
    final seatIncline = _s('seatIncline'); // Droit/Incliné
    final chargerUsb = _s('chargerUsb'); // Oui/Non/Indifférent
    final water = _s('water'); // Non/Plate/Gazeuse
    final snacks = _s('snacks'); // Non/Sucré/Salé

    if (seatPosition != null) chips.add(_GoldPill('Siège : $seatPosition'));
    if (seatIncline != null) chips.add(_GoldPill('Inclinaison : $seatIncline'));
    if (chargerUsb != null) chips.add(_GoldPill('USB : $chargerUsb'));
    if (_b('wifi')) chips.add(_GoldPill('Wi-Fi premium'));
    if (water != null && water != 'Non') chips.add(_GoldPill('Eau : $water'));
    if (snacks != null && snacks != 'Non')
      chips.add(_GoldPill('Snacks : $snacks'));

    // ----- Environnement
    if (_b('smokeFree')) chips.add(_GoldPill('Non-fumeur'));
    if (prefs['disinfected'] == true) chips.add(_GoldPill('Désinfecté'));
    if (prefs['silentRide'] == true) chips.add(_GoldPill('Silence à bord'));
    if (_b('pets')) chips.add(_GoldPill('Animaux acceptés'));

    // ----- Conduite
    final drivingStyle = _s('drivingStyle'); // Douce/Normale/Dynamique
    final avgSpeed = _s('avgSpeed'); // Équilibrée/Rapide
    final suspension = _s('suspension'); // Souple/Sport
    if (drivingStyle != null) chips.add(_GoldPill('Conduite : $drivingStyle'));
    if (avgSpeed != null) chips.add(_GoldPill('Vitesse : $avgSpeed'));
    if (suspension != null) chips.add(_GoldPill('Suspension : $suspension'));

    // ----- Esthétique / véhicule
    if (vehicleType != null) chips.add(_GoldPill('Véhicule : $vehicleType'));
    final interiorColor = _s('interiorColor');
    if (interiorColor != null)
      chips.add(_GoldPill('Intérieur : $interiorColor'));
    if (prefs['preferredDriver'] == true)
      chips.add(_GoldPill('Chauffeur attitré'));

    // Marques préférées (on affiche les 3 premières + “…”)
    final brands = (prefs['brands'] is List)
        ? List<String>.from(prefs['brands'])
        : <String>[];
    if (brands.isNotEmpty) {
      final shown = brands.take(3).join(', ');
      final suffix = brands.length > 3 ? '…' : '';
      chips.add(_GoldPill('Marques : $shown$suffix'));
    }

    // ----- Moto (si Moto)
    if (vehicleType == 'Moto') {
      final helmetType = _s('helmetType');
      final helmetHygiene = _s('helmetHygiene');
      final protections = _s('protections');
      final motoSpeed = _s('motoSpeed');
      final intercom = prefs['intercom'] == true;

      if (helmetType != null) chips.add(_GoldPill('Casque : $helmetType'));
      if (helmetHygiene != null)
        chips.add(_GoldPill('Hygiène : $helmetHygiene'));
      if (protections != null)
        chips.add(_GoldPill('Protections : $protections'));
      if (motoSpeed != null)
        chips.add(_GoldPill('Vitesse (moto) : $motoSpeed'));
      if (intercom) chips.add(_GoldPill('Intercom actif'));
    }

    // ----- Écologie & éthique
    final energyType = _s('energyType'); // Électrique/Hybride/Thermique
    if (energyType != null) chips.add(_GoldPill('Énergie : $energyType'));
    if (prefs['carbonOffset'] == true)
      chips.add(_GoldPill('Compensation carbone'));
    if (prefs['engineSilence'] == true) chips.add(_GoldPill('Silence moteur'));

    // ----- Paiement & réservation
    final paymentMode = _s('paymentMode'); // Automatique/Manuel/Partagé
    final invoiceMethod = _s('invoiceMethod'); // Email/SMS
    final notifications = _s('notifications'); // Push/SMS/Email
    if (paymentMode != null) chips.add(_GoldPill('Paiement : $paymentMode'));
    if (invoiceMethod != null) chips.add(_GoldPill('Facture : $invoiceMethod'));
    if (notifications != null) chips.add(_GoldPill('Notif. : $notifications'));

    // Fallback : si aucune puce
    if (chips.isEmpty) {
      chips.add(
        const Text(
          "Aucune préférence renseignée.",
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: chips,
    );
  }
}
