import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';
import '../services/admin_stats_service.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ✅ Helper dans la classe (pas dans build)
  bool _isDriverComplete(Map<String, dynamic> d) {
    const requiredDocKeys = [
      'driverLicenseUrl',
      'registrationUrl',
      'vehicleInsuranceUrl',
      'proInsuranceUrl',
      'technicalInspectionUrl',
      'maintenanceInvoiceUrl',
      'ribUrl',
      'idCardUrl',
    ];

    final birth = (d['birthdate'] ?? '').toString().trim();
    if (birth.isEmpty) return false;

    final docs = (d['documents'] is Map)
        ? Map<String, dynamic>.from(d['documents'])
        : <String, dynamic>{};

    for (final k in requiredDocKeys) {
      final v = (docs[k] ?? '').toString().trim();
      if (v.isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          // Fond ink premium
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B0B0D), Color(0xFF08080A)],
                ),
              ),
            ),
          ),

          // Orbes dorées
          Positioned(
            right: -160,
            top: -120,
            width: 420,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.gold.withOpacity(.14), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -130,
            width: 380,
            height: 380,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.deepGold.withOpacity(.10),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(context),
                      const SizedBox(height: 12),

                      // KPI grid (lux)
                      AnimatedBuilder(
                        animation: _glow,
                        builder: (_, __) {
                          final glow = 0.08 + 0.10 * _glow.value;
                          return _glass(
                            radius: 22,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            borderGlowOpacity: glow,
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                // KPI Drivers LIVE (cliquable)
                                StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('drivers')
                                      .snapshots(),
                                  builder: (context, snap) {
                                    if (!snap.hasData) {
                                      return const _KpiCard(
                                        title: "Drivers",
                                        value: "…",
                                        icon: Icons.badge_rounded,
                                      );
                                    }

                                    final list = snap.data!.docs
                                        .map((e) => e.data())
                                        .toList();
                                    final total = list.length;
                                    final complete =
                                        list.where(_isDriverComplete).length;
                                    final incomplete = total - complete;

                                    return _KpiCard(
                                      title: "Drivers",
                                      value:
                                          "$total  •  $complete ✅  /  $incomplete ❌",
                                      icon: Icons.badge_rounded,
                                      accent: AppColors.gold,
                                      onTap: () => context.go('/admin/drivers'),
                                    );
                                  },
                                ),

                                // Placeholders premium (tu brancheras plus tard)
// KPI Passagers LIVE (cliquable)
                                StreamBuilder<
                                    QuerySnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('passengers')
                                      .snapshots(),
                                  builder: (context, snap) {
                                    if (!snap.hasData) {
                                      return const _KpiCard(
                                        title: "Passagers",
                                        value: "…",
                                        icon: Icons.people_rounded,
                                        accent: Color(0xFFFFC44D),
                                      );
                                    }

                                    final list = snap.data!.docs
                                        .map((e) => e.data())
                                        .toList();
                                    final total = list.length;

                                    // même logique que ta page passengers : complet = birthdate + address + identityCardUrl
                                    bool _isPassengerComplete(
                                        Map<String, dynamic> d) {
                                      final hasBirth = d['birthdate'] != null;
                                      final address = (d['address'] ?? '')
                                          .toString()
                                          .trim();
                                      final idCard =
                                          (d['identityCardUrl'] ?? '')
                                              .toString()
                                              .trim();
                                      return hasBirth &&
                                          address.isNotEmpty &&
                                          idCard.isNotEmpty;
                                    }

                                    final complete =
                                        list.where(_isPassengerComplete).length;
                                    final incomplete = total - complete;

                                    return _KpiCard(
                                        title: "Passagers",
                                        value:
                                            "$total  •  $complete ✅  /  $incomplete ❌",
                                        icon: Icons.people_rounded,
                                        accent: const Color(0xFFFFC44D),
                                        onTap: () =>
                                            context.go('/admin/passengers'));
                                  },
                                ),

                                FutureBuilder<Map<String, dynamic>>(
                                  future: AdminStatsService.getDashboardStats(
                                      days: 30),
                                  builder: (context, snap) {
                                    if (!snap.hasData) {
                                      return _KpiCard(
                                        title: "Stats",
                                        value: "…",
                                        icon: Icons.query_stats_rounded,
                                        accent: const Color(0xFF45E27A),
                                        onTap: () => context.go('/admin/stats'),
                                      );
                                    }

                                    final data = snap.data!;
                                    final totals = Map<String, dynamic>.from(
                                        data['totals'] ?? {});
                                    final done =
                                        (totals['doneReservations'] ?? 0)
                                            .toString();

                                    // Tu peux afficher ce que tu veux ici (doneReservations est sûr)
                                    return _KpiCard(
                                      title: "Stats",
                                      value: "$done • Terminées (30j)",
                                      icon: Icons.query_stats_rounded,
                                      accent: const Color(0xFF45E27A),
                                      onTap: () => context.go('/admin/stats'),
                                    );
                                  },
                                ),

                                const _KpiCard(
                                  title: "Signalements",
                                  value: "—",
                                  icon: Icons.report_rounded,
                                  accent: Color(0xFFE55B5B),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 14),

                      // Actions rapides
                      const _SectionTitle("Actions rapides"),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ActionTile(
                            icon: Icons.verified_user_rounded,
                            title: "Vérifier documents",
                            subtitle:
                                "Contrôle permis, carte grise, assurances",
                            onTap: () => context.go('/admin/drivers'),
                          ),
                          _ActionTile(
                            icon: Icons.block_rounded,
                            title: "Bloquer un compte",
                            subtitle: "Driver ou passager (à brancher)",
                            onTap: () {},
                          ),
                          _ActionTile(
                            icon: Icons.tune_rounded,
                            title: "Paramètres",
                            subtitle: "Règles, seuils, configurations",
                            onTap: () {},
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Dernières activités
                      const _SectionTitle("Dernières activités"),
                      const SizedBox(height: 10),
                      _glass(
                        radius: 22,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: const [
                            _RowLine("Aucune activité pour l’instant", "—"),
                            SizedBox(height: 10),
                            Divider(color: Colors.white12),
                            SizedBox(height: 10),
                            _RowLine("Prochain ajout : liste Firestore",
                                "drivers/users/reservations"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        const _GoldTitle("Console Super Admin"),
        const SizedBox(width: 10),
        const _LiveChip(),
        const Spacer(),
        _IconGlassBtn(
          icon: Icons.logout_rounded,
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              // retourne au login admin ou login classique selon ton routing
              context.go('/login');
            }
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // GLASS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _glass({
    required double radius,
    required EdgeInsets padding,
    required Widget child,
    double borderGlowOpacity = 0.08,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          colors: [Colors.white.withOpacity(0.06), Colors.black12],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          const BoxShadow(
              color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
          BoxShadow(
            color: AppColors.gold.withOpacity(borderGlowOpacity),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UI Components
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'PlayfairDisplay',
        fontWeight: FontWeight.w900,
        fontSize: 18,
        letterSpacing: .15,
      ),
    );
  }
}

class _GoldTitle extends StatelessWidget {
  final String text;
  const _GoldTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _LiveChip extends StatefulWidget {
  const _LiveChip();

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: .92, end: 1.0)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: const Color(0xFF151515),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF45E27A),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF45E27A).withOpacity(.6),
                  blurRadius: 10,
                )
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            "LIVE",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
            ),
          ),
        ]),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
    this.accent = AppColors.gold,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.06), Colors.black12],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withOpacity(.12),
                  border: Border.all(color: accent.withOpacity(.35)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.06), Colors.black12],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(.22),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    )
                  ],
                ),
                child: Icon(icon, color: Colors.black),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white60, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowLine extends StatelessWidget {
  final String left;
  final String right;
  const _RowLine(this.left, this.right);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Text(left,
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        Text(right,
            style: const TextStyle(
                color: AppColors.gold, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _IconGlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconGlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [Colors.white.withOpacity(.06), Colors.black12],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: AppColors.gold),
      ),
    );
  }
}
