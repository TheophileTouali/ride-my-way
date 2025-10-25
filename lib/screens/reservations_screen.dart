import 'dart:async';

import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../themes/app_theme.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  final Set<String> _redirectedReservationIds = {};
  String _filter = 'À venir';

  void _showPremiumFavoriteOverlay(String message) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: 80,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.favorite, color: Colors.black, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Timer(const Duration(milliseconds: 2500), () => overlayEntry.remove());
  }

  Future<void> _addToFavorites({
    required String from,
    required String to,
    required String frequency,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final existing = await FirebaseFirestore.instance
        .collection('favorites')
        .where('userId', isEqualTo: user.uid)
        .where('from', isEqualTo: from)
        .where('to', isEqualTo: to)
        .get();

    if (existing.docs.isNotEmpty) {
      _showPremiumFavoriteOverlay("Ce trajet est déjà dans vos favoris");
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('favorites').add({
        'userId': user.uid,
        'from': from,
        'to': to,
        'frequency': frequency,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showPremiumFavoriteOverlay("Trajet ajouté à vos favoris");
    } catch (e) {
      // ignore: avoid_print
      print("Erreur lors de l'ajout aux favoris : $e");
    }
  }

  Future<void> _cancelReservation(String docId) async {
    await FirebaseFirestore.instance
        .collection('reservations')
        .doc(docId)
        .update({'status': 'Annulée'});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Réservation annulée'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Stream<QuerySnapshot> _reservationsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .snapshots();
  }

  List<QueryDocumentSnapshot> _filterReservations(
    List<QueryDocumentSnapshot> reservations,
  ) {
    final now = DateTime.now();

    return reservations
        .map((doc) {
          final ts = doc['timestamp'] as Timestamp;
          final date = ts.toDate();
          final status = (doc['status'] ?? '').toString();

          // Si la date est passée et que ce n'est pas annulé/terminé => on termine.
          if (status != 'Annulée' &&
              date.isBefore(now) &&
              status != 'Terminée') {
            FirebaseFirestore.instance
                .collection('reservations')
                .doc(doc.id)
                .update({'status': 'Terminée'});
          }
          return doc;
        })
        .whereType<QueryDocumentSnapshot>()
        .where((doc) {
          final ts = doc['timestamp'] as Timestamp;
          final date = ts.toDate();
          final status = (doc['status'] ?? '').toString();

          if (_filter == 'Tous') return true;
          if (_filter == 'À venir') return date.isAfter(now);
          return status.toLowerCase() == _filter.trim().toLowerCase();
        })
        .toList()
      ..sort((a, b) {
        final tsA = a['timestamp'] as Timestamp;
        final tsB = b['timestamp'] as Timestamp;
        return tsA.toDate().compareTo(tsB.toDate());
      });
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return "${date.day}/${date.month}/${date.year} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }

  String _getFieldOrDefault(
    QueryDocumentSnapshot doc,
    String key,
    String fallback,
  ) {
    return doc.data().toString().contains(key) ? doc[key].toString() : fallback;
  }

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
      body: Stack(
        children: [
          // halo discret premium
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.85, -0.92),
                    radius: 1.2,
                    colors: [
                      AppColors.gold.withOpacity(.06),
                      Colors.transparent
                    ],
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 16),
              _buildFilterChips(),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _reservationsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.gold),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                        child: Text(
                          "Chargement des réservations...",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;

                    // Redirection automatique vers la course active/en route
                    if (_redirectedReservationIds.isEmpty) {
                      // 1) "En cours"
                      final enCoursDocs = docs
                          .where((doc) => doc['status'] == 'En cours')
                          .toList();
                      if (enCoursDocs.isNotEmpty) {
                        enCoursDocs.sort((a, b) {
                          final aTime = (a['timestamp'] as Timestamp).toDate();
                          final bTime = (b['timestamp'] as Timestamp).toDate();
                          return bTime.compareTo(aTime);
                        });
                        final latestDoc = enCoursDocs.first;
                        final id = latestDoc.id;

                        _redirectedReservationIds.add(id);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) context.go('/tracking/$id');
                        });
                        return const SizedBox.shrink();
                      }

                      // 2) "En route"
                      final enRouteDocs = docs
                          .where((doc) => doc['status'] == 'En route')
                          .toList();
                      if (enRouteDocs.isNotEmpty) {
                        enRouteDocs.sort((a, b) {
                          final aTime = (a['timestamp'] as Timestamp).toDate();
                          final bTime = (b['timestamp'] as Timestamp).toDate();
                          return bTime.compareTo(aTime);
                        });
                        final latestDoc = enRouteDocs.first;
                        final id = latestDoc.id;

                        _redirectedReservationIds.add(id);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) context.go('/tracking/$id');
                        });
                        return const SizedBox.shrink();
                      }
                    }

                    final filtered = _filterReservations(docs);
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text(
                          "Aucune réservation pour ce filtre.",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        return FadeInLeft(
                          delay: Duration(milliseconds: index * 100),
                          child: Column(
                            children: [
                              _reservationCard(
                                docId: doc.id,
                                from: doc['from'] ?? '',
                                to: doc['to'] ?? '',
                                date:
                                    _formatDate(doc['timestamp'] as Timestamp),
                                status: _getFieldOrDefault(
                                    doc, 'status', 'En attente'),
                                price: _getFieldOrDefault(
                                    doc, 'price', 'À définir'),
                                vehicle: _getFieldOrDefault(
                                    doc, 'vehicle', 'Non assigné'),
                                driver: _getFieldOrDefault(
                                    doc, 'driverName', 'Non assigné'),
                                distanceOpt:
                                    _getFieldOrDefault(doc, 'distance', ''),
                                docSnapshot: doc,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------- Filtres premium -------
  Widget _buildFilterChips() {
    final statuses = [
      'À venir',
      'Confirmée',
      'En attente',
      'Annulée',
      'Terminée',
      'Tous'
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: statuses.length,
        itemBuilder: (_, i) {
          final s = statuses[i];
          final selected = _filter == s;

          return GestureDetector(
            onTap: () => setState(() => _filter = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: selected ? _GoldGrad.g : null,
                color: selected ? null : const Color(0xFF1B1B1B),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: selected ? const Color(0xFFFFE680) : Colors.white10),
                boxShadow: selected
                    ? [
                        BoxShadow(
                            color: AppColors.gold.withOpacity(.22),
                            blurRadius: 16,
                            offset: const Offset(0, 6))
                      ]
                    : [
                        BoxShadow(
                            color: Colors.black.withOpacity(.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4))
                      ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (selected) ...[
                  const Icon(Icons.check_rounded,
                      size: 16, color: Colors.black),
                  const SizedBox(width: 6),
                ],
                Text(
                  s,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 14.5,
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // --- (ancienne) pastille simple — plus utilisée mais on la garde si besoin ---
  Widget _pill(
    String text, {
    Color bg = const Color(0xFF2A2A2A),
    Color fg = Colors.white70,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ------- Carte premium -------
  Widget _reservationCard({
    required String docId,
    required String from,
    required String to,
    required String date,
    required String status,
    required String price,
    required String vehicle,
    required String driver,
    required QueryDocumentSnapshot docSnapshot,
    String? distanceOpt, // km éventuels stockés dans le doc
  }) {
    // Statut paiement
    final paymentStatus =
        (docSnapshot.data().toString().contains('paymentStatus'))
            ? (docSnapshot['paymentStatus'] as String? ?? '')
            : '';
    final bool isAuthorized = paymentStatus == 'authorized';
    final bool isCaptured = paymentStatus == 'succeeded';

    final priceStr = (price.isEmpty) ? '—' : price;
    final String? distanceStr = () {
      final d = distanceOpt?.toString().trim();
      if (d == null || d.isEmpty) return null;
      // si c'est déjà "26.2" on ajoute " km"
      return d.contains('km')
          ? d
          : "${double.tryParse(d)?.toStringAsFixed(1) ?? d} km";
    }();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête + pilules
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                  border: Border.all(color: AppColors.gold, width: 1.2),
                ),
                child: const Icon(Icons.location_on,
                    size: 16, color: AppColors.gold),
              ),
              const SizedBox(width: 10),
              const Expanded(child: _GoldTitle("Détails de la réservation")),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (distanceStr != null) ...[
                  _DistancePill("~$distanceStr"),
                  const SizedBox(width: 8),
                ],
                _PricePill("${priceStr.toString().replaceAll('.', ',')} €"),
              ]),
            ],
          ),
          const SizedBox(height: 14),

          // Trajet (timeline)
          _TimelineMini(from: from, to: to),
          const SizedBox(height: 12),

          // Infos lignes
          Row(children: [
            const Icon(Icons.event_rounded, color: Colors.white60, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text("Départ : $date",
                    style: const TextStyle(color: Colors.white70))),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.directions_car_filled_rounded,
                color: Colors.white60, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text("Véhicule : $vehicle",
                    style: const TextStyle(color: Colors.white70))),
          ]),
          Row(children: [
            const Icon(Icons.person_outline_rounded,
                color: Colors.white60, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text("Conducteur : $driver",
                    style: const TextStyle(color: Colors.white70))),
          ]),

          const SizedBox(height: 12),

          // Statuts
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _StatusChip(status),
              if (isCaptured)
                const _Pill('Payé',
                    icon: Icons.verified_rounded,
                    fg: Colors.greenAccent,
                    bg: Color(0x2228A745)),
              if (isAuthorized && !isCaptured)
                _Pill('Préautorisé',
                    icon: Icons.lock_clock_rounded,
                    fg: Colors.white70,
                    bg: Colors.blueGrey.shade800),
            ],
          ),

          const SizedBox(height: 14),

          // Actions
          Row(
            children: [
              if (status != 'Annulée' && status != 'Terminée')
                TextButton.icon(
                  onPressed: () => _cancelReservation(docId),
                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                  label: const Text("Annuler",
                      style: TextStyle(color: Colors.redAccent)),
                ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _addToFavorites(
                    from: from, to: to, frequency: 'Ponctuelle'),
                icon: const Icon(Icons.favorite_border, color: Colors.black),
                label: const Text(
                  "Favori",
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),

          if (status == 'Arrivé') const SizedBox(height: 6),
          if (status == 'Arrivé')
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('reservations')
                    .doc(docId)
                    .update({'status': 'En cours'});
                _showPremiumFavoriteOverlay("Trajet démarré !");
              },
              icon: const Icon(Icons.directions_car, color: Colors.black),
              label: const Text(
                "Je monte",
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

          if (status == 'En cours') const SizedBox(height: 6),
          if (status == 'En cours')
            ElevatedButton.icon(
              onPressed: () => context.go('/tracking/$docId'),
              icon: const Icon(Icons.navigation, color: Colors.black),
              label: const Text(
                "Suivre le trajet",
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}

/* ========= PREMIUM UI HELPERS ========= */

class _GoldGrad {
  static const LinearGradient g = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _GlassCard(
      {required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withOpacity(0.18), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.45),
              blurRadius: 24,
              offset: const Offset(0, 16)),
          BoxShadow(
              color: Colors.black.withOpacity(.25),
              blurRadius: 8,
              spreadRadius: -6,
              offset: const Offset(0, -2)),
        ],
      ),
      child: child,
    );
  }
}

class _GoldTitle extends StatelessWidget {
  final String text;
  const _GoldTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => _GoldGrad.g.createShader(r),
      child: const Text(
        "Détails de la réservation",
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w800,
          fontSize: 18.5,
          height: 1.15,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color fg;
  final Gradient? gradient;
  final Color? bg;
  final EdgeInsets pad;
  const _Pill(this.text,
      {this.icon,
      this.fg = Colors.white,
      this.gradient,
      this.bg,
      this.pad = const EdgeInsets.symmetric(horizontal: 12, vertical: 7)});
  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: gradient == null ? (bg ?? const Color(0xFF1A1A1A)) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
          color: gradient == null ? Colors.white10 : const Color(0xFFFFE680),
          width: 1),
      boxShadow: gradient == null
          ? [
              BoxShadow(
                  color: Colors.black.withOpacity(.24),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ]
          : [
              BoxShadow(
                  color: AppColors.gold.withOpacity(.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ],
    );
    return Container(
      padding: pad,
      decoration: deco,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Text(text,
            style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontFamily: 'PlayfairDisplay')),
      ]),
    );
  }
}

class _PricePill extends _Pill {
  _PricePill(String v) : super(v, fg: Colors.black, gradient: _GoldGrad.g);
}

class _DistancePill extends _Pill {
  _DistancePill(String v)
      : super(
          v,
          fg: AppColors.gold,
          bg: const Color(0xFF131313),
          pad: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'Confirmée':
        return const _Pill('Confirmée',
            icon: Icons.verified_rounded,
            fg: Colors.black,
            gradient: _GoldGrad.g);
      case 'En attente':
        return _Pill('En attente',
            icon: Icons.hourglass_bottom_rounded,
            fg: Colors.amberAccent,
            bg: Colors.amber.withOpacity(.12));
      case 'Annulée':
        return _Pill('Annulée',
            icon: Icons.cancel,
            fg: Colors.redAccent,
            bg: Colors.red.withOpacity(.10));
      case 'Terminée':
        return _Pill('Terminée',
            icon: Icons.check_circle,
            fg: Colors.greenAccent,
            bg: Colors.green.withOpacity(.10));
      default:
        return _Pill(status, fg: Colors.white70, bg: const Color(0xFF2A2A2A));
    }
  }
}

class _TimelineMini extends StatelessWidget {
  final String from;
  final String to;
  const _TimelineMini({required this.from, required this.to});
  @override
  Widget build(BuildContext context) {
    Widget dot() => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _GoldGrad.g,
            border: Border.all(color: const Color(0xFFFFEAB0), width: 1),
            boxShadow: [
              BoxShadow(
                  color: AppColors.gold.withOpacity(.35),
                  blurRadius: 6,
                  spreadRadius: 1)
            ],
          ),
        );
    final label = TextStyle(
      color: AppColors.gold.withOpacity(.95),
      fontWeight: FontWeight.w700,
      fontSize: 12,
      letterSpacing: .2,
    );
    const value = TextStyle(
      color: Colors.white,
      fontSize: 15.5,
      fontFamily: 'PlayfairDisplay',
      fontWeight: FontWeight.w700,
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          dot(),
          Container(
              width: 2,
              height: 22,
              decoration: BoxDecoration(
                  gradient: _GoldGrad.g,
                  borderRadius: BorderRadius.circular(2))),
          dot(),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Départ', style: label),
              const SizedBox(height: 2),
              Text(from, maxLines: 1, style: value),
              const SizedBox(height: 8),
              Text('Arrivée', style: label),
              const SizedBox(height: 2),
              Text(to, maxLines: 1, style: value),
            ],
          ),
        ),
      ],
    );
  }
}
