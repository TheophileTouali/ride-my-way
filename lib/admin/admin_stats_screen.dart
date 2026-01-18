import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/admin_stats_service.dart';
import '../themes/app_theme.dart';

class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  int _days = 180;

  /// null => Tous les chauffeurs
  String? _selectedDriverId;

  /// UI label (évite de re-scan la liste à chaque build)
  String _selectedDriverLabel = "Tous les chauffeurs";

  /// ✅ évite de rappeler la function à chaque rebuild

  late Future<Map<String, dynamic>> _futureGlobal;
  Future<Map<String, dynamic>>? _futureDriver;

  /// ✅ liste chauffeurs (pour le sélecteur)
  late Future<List<_DriverItem>> _driversFuture;
  List<_DriverItem> _driversCache = const [];

  @override
  void initState() {
    super.initState();
    _driversFuture = _fetchDrivers().then((list) {
      _driversCache = list;
      _syncSelectedLabel();
      return list;
    });

    _futureGlobal =
        AdminStatsService.getDashboardStats(days: _days, driverId: null);
    _futureDriver = null;
  }

  void _reload({int? days, String? driverId}) {
    setState(() {
      if (days != null) _days = days;

      _selectedDriverId = driverId;
      _syncSelectedLabel();

      // ✅ Global toujours refreshé
      _futureGlobal = AdminStatsService.getDashboardStats(
        days: _days,
        driverId: null,
      );

      // ✅ Driver uniquement si sélection
      _futureDriver = (_selectedDriverId == null)
          ? null
          : AdminStatsService.getDashboardStats(
              days: _days,
              driverId: _selectedDriverId,
            );
    });
  }

  void _syncSelectedLabel() {
    if (_selectedDriverId == null) {
      _selectedDriverLabel = "Tous les chauffeurs";
      return;
    }
    final match =
        _driversCache.where((d) => d.id == _selectedDriverId).toList();
    if (match.isNotEmpty) {
      _selectedDriverLabel = match.first.label;
    } else {
      _selectedDriverLabel = _selectedDriverId!;
    }
  }

  // ───────────────────────── Business helpers ─────────────────────────

  // Format € simple (sans intl)
  String _money(num v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final dec = parts.length > 1 ? parts[1] : "00";

    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final idx = whole.length - i;
      buf.write(whole[i]);
      if (idx > 1 && idx % 3 == 1) buf.write(' ');
    }
    return "${buf.toString()},$dec €";
  }

  // ───────────────────────── Data helpers ─────────────────────────

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is List) {
      return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return <Map<String, dynamic>>[];
  }

  num _sum(List items, String key) {
    num t = 0;
    for (final e in items) {
      if (e is Map && e[key] != null) {
        final n = e[key];
        t += (n is num) ? n : (num.tryParse(n.toString()) ?? 0);
      }
    }
    return t;
  }

  int _sumInt(List items, String key) {
    int t = 0;
    for (final e in items) {
      if (e is Map && e[key] != null) {
        final n = e[key];
        t += (n is num) ? n.toInt() : (int.tryParse(n.toString()) ?? 0);
      }
    }
    return t;
  }

  Future<List<_DriverItem>> _fetchDrivers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .limit(250)
          .get();

      final items = <_DriverItem>[];
      for (final doc in snap.docs) {
        final data = doc.data();

        final first =
            (data['firstName'] ?? data['prenom'] ?? '').toString().trim();
        final last = (data['lastName'] ?? data['nom'] ?? '').toString().trim();
        final full = ("$first $last").trim();

        final email = (data['email'] ?? '').toString().trim();
        final label =
            full.isNotEmpty ? full : (email.isNotEmpty ? email : doc.id);

        items.add(_DriverItem(id: doc.id, label: label));
      }

      items.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      return items;
    } catch (_) {
      // si Firestore n'est pas prêt / règle / etc, on évite de bloquer l'écran
      return <_DriverItem>[];
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B0B0D), Color(0xFF07070A)],
                ),
              ),
            ),
          ),

          // orbes premium
          Positioned(
            right: -170,
            top: -140,
            width: 460,
            height: 460,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.gold.withOpacity(.16), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            left: -140,
            bottom: -150,
            width: 420,
            height: 420,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.deepGold.withOpacity(.11),
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
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _topBar(context),
                      const SizedBox(height: 14),

                      // Header premium + chips + driver picker
                      _glass(
                        radius: 26,
                        padding: const EdgeInsets.all(14),
                        child: _headerBar(),
                      ),

                      const SizedBox(height: 14),

                      FutureBuilder<Map<String, dynamic>>(
                        future: _futureGlobal,
                        builder: (context, snapGlobal) {
                          if (snapGlobal.connectionState ==
                              ConnectionState.waiting) {
                            return _glass(
                              radius: 22,
                              padding: const EdgeInsets.all(18),
                              child: const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 26),
                                  child: CircularProgressIndicator(
                                      color: AppColors.gold),
                                ),
                              ),
                            );
                          }

                          if (snapGlobal.hasError) {
                            return _glass(
                              radius: 22,
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Erreur de chargement (global)",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "${snapGlobal.error}",
                                    style: const TextStyle(
                                        color: Colors.white60, height: 1.25),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => _reload(
                                          days: _days,
                                          driverId: _selectedDriverId),
                                      icon: const Icon(Icons.refresh_rounded,
                                          color: AppColors.gold),
                                      label: const Text(
                                        "Réessayer",
                                        style: TextStyle(
                                            color: AppColors.gold,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final global =
                              Map<String, dynamic>.from(snapGlobal.data ?? {});
                          final globalTotals =
                              Map<String, dynamic>.from(global['totals'] ?? {});
                          final globalResByStatus =
                              _asMap(global['reservationsByStatus']);
                          final globalDriversByVerif =
                              _asMap(global['driversByVerification']);

                          Widget globalBlock() => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _section("Vue globale"),
                                  const SizedBox(height: 10),
                                  _kpiGrid(globalTotals),
                                  const SizedBox(height: 14),

                                  _section("Réservations (global)"),
                                  const SizedBox(height: 10),
                                  _glass(
                                    radius: 22,
                                    padding: const EdgeInsets.all(14),
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _pill(
                                            "En attente",
                                            globalResByStatus['pending'] ?? 0,
                                            const Color(0xFFFFC44D)),
                                        _pill(
                                            "Confirmée",
                                            globalResByStatus['confirmed'] ?? 0,
                                            const Color(0xFF45E27A)),
                                        _pill(
                                            "En route",
                                            globalResByStatus['enRoute'] ?? 0,
                                            const Color(0xFF6AA9FF)),
                                        _pill(
                                            "Prêt",
                                            globalResByStatus['pret'] ?? 0,
                                            const Color(0xFFB58BFF)),
                                        _pill(
                                            "En cours",
                                            globalResByStatus['enCours'] ?? 0,
                                            const Color(0xFFFF7BB0)),
                                        _pill(
                                            "Terminée",
                                            globalResByStatus['terminee'] ?? 0,
                                            const Color(0xFF45E27A)),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  _section("KYC Conducteurs (global)"),
                                  const SizedBox(height: 10),
                                  _glass(
                                    radius: 22,
                                    padding: const EdgeInsets.all(14),
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _pill(
                                            "Verified",
                                            globalDriversByVerif['verified'] ??
                                                0,
                                            const Color(0xFF45E27A)),
                                        _pill(
                                            "Pending",
                                            globalDriversByVerif['pending'] ??
                                                0,
                                            const Color(0xFFFFC44D)),
                                        _pill(
                                            "Rejected",
                                            globalDriversByVerif['rejected'] ??
                                                0,
                                            const Color(0xFFE55B5B)),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  // ✅ Business global
                                  _buildBusinessStats(global),
                                ],
                              );

                          // ✅ Si pas de driver sélectionné → uniquement global
                          if (_futureDriver == null) return globalBlock();

                          // ✅ Sinon → on charge driver ET on affiche les deux
                          return FutureBuilder<Map<String, dynamic>>(
                            future: _futureDriver,
                            builder: (context, snapDriver) {
                              if (snapDriver.connectionState ==
                                  ConnectionState.waiting) {
                                // on montre global + un loader discret pour la partie driver
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    globalBlock(),
                                    const SizedBox(height: 16),
                                    _glass(
                                      radius: 22,
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        children: const [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.gold,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              "Chargement des stats chauffeur…",
                                              style: TextStyle(
                                                color: Colors.white60,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }

                              if (snapDriver.hasError) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    globalBlock(),
                                    const SizedBox(height: 16),
                                    _glass(
                                      radius: 22,
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Erreur stats chauffeur",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "${snapDriver.error}",
                                            style: const TextStyle(
                                                color: Colors.white60),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }

                              final driver = Map<String, dynamic>.from(
                                  snapDriver.data ?? {});
                              final driverTotals = Map<String, dynamic>.from(
                                  driver['totals'] ?? {});
                              final driverResByStatus =
                                  _asMap(driver['reservationsByStatus']);

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  globalBlock(),
                                  const SizedBox(height: 18),

                                  _section(
                                      "Vue chauffeur • $_selectedDriverLabel"),
                                  const SizedBox(height: 10),
                                  _kpiGrid(driverTotals),
                                  const SizedBox(height: 14),

                                  _section("Réservations (chauffeur)"),
                                  const SizedBox(height: 10),
                                  _glass(
                                    radius: 22,
                                    padding: const EdgeInsets.all(14),
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        _pill(
                                            "En attente",
                                            driverResByStatus['pending'] ?? 0,
                                            const Color(0xFFFFC44D)),
                                        _pill(
                                            "Confirmée",
                                            driverResByStatus['confirmed'] ?? 0,
                                            const Color(0xFF45E27A)),
                                        _pill(
                                            "En route",
                                            driverResByStatus['enRoute'] ?? 0,
                                            const Color(0xFF6AA9FF)),
                                        _pill(
                                            "Prêt",
                                            driverResByStatus['pret'] ?? 0,
                                            const Color(0xFFB58BFF)),
                                        _pill(
                                            "En cours",
                                            driverResByStatus['enCours'] ?? 0,
                                            const Color(0xFFFF7BB0)),
                                        _pill(
                                            "Terminée",
                                            driverResByStatus['terminee'] ?? 0,
                                            const Color(0xFF45E27A)),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  // ✅ Business chauffeur (hyper pro)
                                  _buildBusinessStats(driver),
                                ],
                              );
                            },
                          );
                        },
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

  Widget _headerBar() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 760;

        final title = Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withOpacity(.18),
                    AppColors.deepGold.withOpacity(.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: AppColors.gold.withOpacity(.25)),
              ),
              child: const Icon(
                Icons.query_stats_rounded,
                color: AppColors.gold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDriverId == null
                        ? "Stats admin • période glissante"
                        : "Stats chauffeur • période glissante",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedDriverId == null
                        ? "Vue globale • revenus & quinzaines"
                        : "Vue filtrée • ${_selectedDriverLabel}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.55),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final chips = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chipDays(30),
            _chipDays(90),
            _chipDays(180),
            _chipDays(365),
          ],
        );

        final selector = Align(
          alignment: Alignment.centerRight,
          child: _driverSelectorButton(),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              chips,
              const SizedBox(height: 12),
              selector,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            chips,
            const SizedBox(width: 14),
            selector,
          ],
        );
      },
    );
  }

  // ───────────────────────── Business UI ─────────────────────────

  Widget _buildBusinessStats(Map<String, dynamic> data) {
    // backend adminGetDashboardStats renvoie:
    // - series: { byDay[], byMonth[] }
    // - fortnights[]
    // - byDriver[]
    final series = _asMap(data['series']);
    final byDay = _asList(series['byDay']);
    final byMonth = _asList(series['byMonth']);
    final fortnights = _asList(data['fortnights']);
    final byDriver = _asList(data['byDriver']);

    // ✅ DEFAULT 0 si vide
    final gross = byDay.isEmpty ? 0 : _sum(byDay, 'gross');
    final driverNet = byDay.isEmpty ? 0 : _sum(byDay, 'driverNet');
    final platform = byDay.isEmpty ? 0 : _sum(byDay, 'platform');
    final rides = byDay.isEmpty ? 0 : _sumInt(byDay, 'rides');

    final lastDays =
        byDay.length <= 14 ? byDay : byDay.sublist(byDay.length - 14);
    final lastMonths =
        byMonth.length <= 12 ? byMonth : byMonth.sublist(byMonth.length - 12);

    // ✅ informatif si vraiment vide
    final emptyBusiness = byDay.isEmpty &&
        byMonth.isEmpty &&
        fortnights.isEmpty &&
        byDriver.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section("Business stats"),
        const SizedBox(height: 10),

        _glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withOpacity(.10),
                  border: Border.all(color: AppColors.gold.withOpacity(.25)),
                ),
                child:
                    const Icon(Icons.payments_rounded, color: AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  emptyBusiness
                      ? "Aucune course terminée sur la période sélectionnée.\nLes chiffres restent affichés à 0."
                      : (_selectedDriverId == null
                          ? "Synthèse revenus • plateforme & chauffeurs."
                          : "Synthèse revenus • chauffeur sélectionné."),
                  style: const TextStyle(
                    color: Colors.white60,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_selectedDriverId != null)
                TextButton.icon(
                  onPressed: () => _reload(driverId: null),
                  icon: const Icon(Icons.close_rounded, color: AppColors.gold),
                  label: const Text(
                    "Reset",
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        _kpiBusinessGrid(
          gross: gross,
          driverNet: driverNet,
          platform: platform,
          rides: rides,
        ),

        const SizedBox(height: 14),

        // Graph day
        _section("Revenus par jour (14 derniers jours)"),
        const SizedBox(height: 10),
        _glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: _MiniBars(
            items: lastDays,
            labelKey: 'key',
            valueKey: 'driverNet',
            valueLabel: "DriverNet",
            emptyHint: "Aucune donnée sur la période.",
          ),
        ),
        const SizedBox(height: 14),

        // Graph month
        _section("Revenus par mois (12 derniers mois)"),
        const SizedBox(height: 10),
        _glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: _MiniBars(
            items: lastMonths,
            labelKey: 'key',
            valueKey: 'driverNet',
            valueLabel: "DriverNet",
            emptyHint: "Aucune donnée sur la période.",
          ),
        ),
        const SizedBox(height: 14),

        // Fortnights
        _section("Quinzaines (payouts)"),
        const SizedBox(height: 10),
        _glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: fortnights.isEmpty
              ? const Text(
                  "Aucune course terminée sur la période.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: fortnights.reversed.map((f) {
                    final key = (f['key'] ?? '').toString();
                    final label = (f['label'] ?? key).toString();

                    final fGross = (f['gross'] ?? 0) as num;
                    final fDriver = (f['driverNet'] ?? 0) as num;
                    final fPlat = (f['platform'] ?? 0) as num;
                    final fRides = (f['rides'] ?? 0).toString();

                    final payouts = _asList(f['payouts']);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: Colors.white.withOpacity(.035),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                                _BadgePill(
                                  text: "$fRides courses",
                                  color: const Color(0xFFFFC44D),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _pillMoney(
                                  "Gross",
                                  _money(fGross),
                                  const Color(0xFFFFD700),
                                ),
                                _pillMoney(
                                  "À payer (Driver)",
                                  _money(fDriver),
                                  const Color(0xFF45E27A),
                                ),
                                _pillMoney(
                                  "Plateforme",
                                  _money(fPlat),
                                  const Color(0xFF6AA9FF),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(color: Colors.white12),
                            const SizedBox(height: 10),
                            const Text(
                              "Détail chauffeurs à payer",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (payouts.isEmpty)
                              const Text(
                                "Aucun payout driver.",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              Column(
                                children: payouts.take(12).map((p) {
                                  final driverId =
                                      (p['driverId'] ?? '').toString();
                                  final pNet = (p['driverNet'] ?? 0) as num;
                                  final pRides = (p['rides'] ?? 0).toString();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "• $driverId",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          pRides,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _money(pNet),
                                          style: const TextStyle(
                                            color: AppColors.gold,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 14),

        // Ranking drivers
        _section("Classement chauffeurs (driverNet)"),
        const SizedBox(height: 10),
        _glass(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: byDriver.isEmpty
              ? const Text(
                  "Aucun driver sur la période.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Column(
                  children:
                      byDriver.take(20).toList().asMap().entries.map((entry) {
                    final i = entry.key;
                    final d = entry.value;

                    final driverId = (d['driverId'] ?? '').toString();
                    final dNet = (d['driverNet'] ?? 0) as num;
                    final dGross = (d['gross'] ?? 0) as num;
                    final dRides = (d['rides'] ?? 0).toString();

                    final isSelected = _selectedDriverId != null &&
                        driverId == _selectedDriverId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: isSelected
                              ? AppColors.gold.withOpacity(.10)
                              : Colors.white.withOpacity(.035),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.gold.withOpacity(.40)
                                : Colors.white10,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.gold.withOpacity(.12),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(.35),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  "${i + 1}",
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    driverId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "$dRides courses • gross ${_money(dGross)}",
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _money(dNet),
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  // ───────────────────────── Driver selector (premium) ─────────────────────────

  Widget _driverSelectorButton() {
    return FutureBuilder<List<_DriverItem>>(
      future: _driversFuture,
      builder: (context, snap) {
        final loaded = snap.connectionState == ConnectionState.done;
        final items = snap.data ?? const <_DriverItem>[];
        if (loaded && _driversCache.isEmpty && items.isNotEmpty) {
          _driversCache = items;
          _syncSelectedLabel();
        }

        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _openDriverPicker(items),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withOpacity(.06),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_taxi_rounded,
                    color: AppColors.gold, size: 18),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    _selectedDriverLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.gold.withOpacity(.9),
                ),
                if (_selectedDriverId != null) ...[
                  const SizedBox(width: 8),

                  // ✅ Intercepte le tap pour éviter d'ouvrir le picker
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _reload(driverId: null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: AppColors.gold.withOpacity(.10),
                        border:
                            Border.all(color: AppColors.gold.withOpacity(.25)),
                      ),
                      child: const Text(
                        "Reset",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDriverPicker(List<_DriverItem> items) async {
    final selected = await showModalBottomSheet<_DriverPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _DriverPickerSheet(
          currentId: _selectedDriverId,
          items: items,
        );
      },
    );

    if (selected == null) return;

    // null => Tous
    _reload(driverId: selected.driverId);
  }

  // ───────────────────────── Common UI helpers ─────────────────────────

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => context.go('/admin'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withOpacity(.06),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              children: [
                Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.gold, size: 16),
                SizedBox(width: 8),
                Text(
                  "Retour",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: _GoldTitle("Stats")),
      ],
    );
  }

  Widget _chipDays(int d) {
    final selected = _days == d;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _reload(days: d, driverId: _selectedDriverId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.white.withOpacity(.06),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.white10,
          ),
        ),
        child: Text(
          "${d}j",
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w900,
          fontSize: 18,
          letterSpacing: .15,
        ),
      );

  Widget _kpiGrid(Map<String, dynamic> totals) {
    final drivers = (totals['drivers'] ?? 0).toString();
    final users = (totals['users'] ?? 0).toString();
    final reservations = (totals['reservations'] ?? 0).toString();

    final feedbacks = (totals['feedbacks'] ?? 0).toString();

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;

        int columns = 4;
        if (w < 520)
          columns = 1;
        else if (w < 860) columns = 2;

        final gap = 12.0;
        final cardW = (w - (gap * (columns - 1))) / columns;

        Widget item(Widget child) => SizedBox(width: cardW, child: child);

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            item(_kpiLux(
              title: "Drivers",
              value: drivers,
              icon: Icons.badge_rounded,
              accent: const Color(0xFFFFD700),
              subtitle: "Chauffeurs enregistrés",
            )),
            item(_kpiLux(
              title: "Users",
              value: users,
              icon: Icons.people_alt_rounded,
              accent: const Color(0xFF6AA9FF),
              subtitle: "Utilisateurs actifs",
            )),
            item(_kpiLux(
              title: "Reservations",
              value: reservations,
              icon: Icons.receipt_long_rounded,
              accent: const Color(0xFF45E27A),
              subtitle: "Courses créées",
            )),
            item(_kpiLux(
              title: "Feedbacks",
              value: feedbacks,
              icon: Icons.star_rounded,
              accent: const Color(0xFFFF7BB0),
              subtitle: "Avis collectés",
            )),
          ],
        );
      },
    );
  }

  Widget _kpiLux({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    String? subtitle,
  }) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(.07),
            Colors.white.withOpacity(.03),
            Colors.black.withOpacity(.20),
          ],
        ),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(.10),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
          const BoxShadow(
            color: Color(0x44000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -60,
              top: -60,
              width: 160,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withOpacity(.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _KpiLuxBorderPainter(accent: accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(.10),
                      border: Border.all(color: accent.withOpacity(.35)),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(.12),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.72),
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent,
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withOpacity(.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontFamily: 'PlayfairDisplay',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: .2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.40),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String title, String value, IconData icon) {
    return SizedBox(
      width: 250,
      child: _glass(
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(.12),
                border: Border.all(color: AppColors.gold.withOpacity(.35)),
              ),
              child: Icon(icon, color: AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Ultra premium business KPIs grid (responsive + elegant)
// Usage:
// _kpiBusinessGrid(gross: gross, driverNet: driverNet, platform: platform, rides: rides),
  Widget _kpiBusinessGrid({
    required num gross,
    required num driverNet,
    required num platform,
    required int rides,
  }) {
    Widget tile({
      required String title,
      required String value,
      required IconData icon,
      required Color dot,
      required List<Color> glow,
      String? micro,
    }) {
      return _glass(
        radius: 22,
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            // soft glow
            Positioned(
              right: -36,
              top: -36,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glow.first.withOpacity(.18),
                      glow.last.withOpacity(.02),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // content
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // icon capsule
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(.10),
                        Colors.white.withOpacity(.04),
                      ],
                    ),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: dot.withOpacity(.18),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Icon(icon, color: AppColors.gold, size: 24),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: dot.withOpacity(.45),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // texts
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontFamily: 'PlayfairDisplay',
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          height: 1.05,
                        ),
                      ),
                      if (micro != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          micro,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.45),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // bottom gold hairline
            Positioned(
              left: 14,
              right: 14,
              bottom: 10,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.gold.withOpacity(.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final items = <Widget>[
      tile(
        title: "Gross",
        value: _money(gross),
        icon: Icons.payments_rounded,
        dot: const Color(0xFFFFD700),
        glow: const [Color(0xFFFFE08A), Color(0xFFA87C00)],
        micro: "Total encaissé",
      ),
      tile(
        title: "Driver (60%)",
        value: _money(driverNet),
        icon: Icons.directions_car_rounded,
        dot: const Color(0xFF45E27A),
        glow: const [Color(0xFF66F0A1), Color(0xFF1E9B57)],
        micro: "À payer chauffeurs",
      ),
      tile(
        title: "Plateforme (40%)",
        value: _money(platform),
        icon: Icons.account_balance_rounded,
        dot: const Color(0xFF6AA9FF),
        glow: const [Color(0xFF8BC2FF), Color(0xFF2F6BFF)],
        micro: "Commission Ride My Way",
      ),
      tile(
        title: "Courses (Terminées)",
        value: "$rides",
        icon: Icons.flag_rounded,
        dot: const Color(0xFFB58BFF),
        glow: const [Color(0xFFCA8FFF), Color(0xFF6C4DFF)],
        micro: "Volume période",
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w >= 980
            ? 4
            : w >= 720
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 2.6 : (cols == 2 ? 2.9 : 3.1),
          ),
          itemBuilder: (_, i) => items[i],
        );
      },
    );
  }

  Widget _pill(String label, dynamic value, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(.05),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.withOpacity(.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "$value",
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillMoney(String label, String value, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(.05),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.withOpacity(.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glass({
    required double radius,
    required EdgeInsets padding,
    required Widget child,
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 6),
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

// ───────────────────────── Small models/widgets ─────────────────────────

class _DriverItem {
  final String id;
  final String label;
  const _DriverItem({required this.id, required this.label});
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
          fontSize: 26,
          fontFamily: 'PlayfairDisplay',
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String text;
  final Color color;
  const _BadgePill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(.12),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String labelKey; // "key"
  final String valueKey; // "driverNet"/"gross"/"platform"
  final String valueLabel;
  final String emptyHint;

  const _MiniBars({
    required this.items,
    required this.labelKey,
    required this.valueKey,
    required this.valueLabel,
    required this.emptyHint,
  });

  num _num(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      // premium placeholder (pas juste un texte brut)
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withOpacity(.035),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(.35),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                emptyHint,
                style: const TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    num maxV = 0;
    for (final e in items) {
      final v = _num(e, valueKey);
      if (v > maxV) maxV = v;
    }
    final safeMax = maxV <= 0 ? 1 : maxV;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          valueLabel,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: items.map((e) {
              final label = (e[labelKey] ?? '').toString();
              final v = _num(e, valueKey);
              final h = (v / safeMax).clamp(0, 1) * 142.0;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: h.toDouble(),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFFE08A).withOpacity(.96),
                              const Color(0xFFA87C00).withOpacity(.96),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(.16),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label.length > 7
                            ? label.substring(label.length - 5)
                            : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Driver Picker Sheet (Search + Premium) ─────────────────────────

class _DriverPickResult {
  final String? driverId;
  const _DriverPickResult(this.driverId);
}

class _DriverPickerSheet extends StatefulWidget {
  final String? currentId;
  final List<_DriverItem> items;

  const _DriverPickerSheet({
    required this.currentId,
    required this.items,
  });

  @override
  State<_DriverPickerSheet> createState() => _DriverPickerSheetState();
}

class _DriverPickerSheetState extends State<_DriverPickerSheet> {
  final _ctrl = TextEditingController();
  String _q = "";

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final filtered = _q.trim().isEmpty
        ? widget.items
        : widget.items
            .where((d) => d.label.toLowerCase().contains(_q.toLowerCase()))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: const Color(0xFF0B0B0D).withOpacity(.92),
          border: Border.all(color: Colors.white10),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 26,
              offset: Offset(0, 16),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // handle
                const SizedBox(height: 10),
                Container(
                  width: 60,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withOpacity(.12),
                  ),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.local_taxi_rounded,
                          color: AppColors.gold),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Sélectionner un chauffeur",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70),
                      )
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(.06),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: Colors.white60),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            onChanged: (v) => setState(() => _q = v),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                            decoration: const InputDecoration(
                              hintText: "Rechercher (nom, email...)",
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_q.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() => _q = "");
                            },
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white60),
                          ),
                      ],
                    ),
                  ),
                ),

                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    children: [
                      _optionTile(
                        context,
                        title: "Tous les chauffeurs",
                        subtitle: "Vue globale (admin)",
                        selected: widget.currentId == null,
                        onTap: () => Navigator.pop(
                          context,
                          const _DriverPickResult(null),
                        ),
                        leading: Icons.all_inclusive_rounded,
                      ),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white.withOpacity(.035),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: const Text(
                              "Aucun chauffeur trouvé.",
                              style: TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      else
                        ...filtered.map((d) {
                          final isSel = widget.currentId == d.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _optionTile(
                              context,
                              title: d.label,
                              subtitle: d.id,
                              selected: isSel,
                              onTap: () => Navigator.pop(
                                context,
                                _DriverPickResult(d.id),
                              ),
                              leading: Icons.person_rounded,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required IconData leading,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? AppColors.gold.withOpacity(.10)
              : Colors.white.withOpacity(.035),
          border: Border.all(
            color: selected ? AppColors.gold.withOpacity(.35) : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(.10),
                border: Border.all(color: AppColors.gold.withOpacity(.25)),
              ),
              child: Icon(leading, color: AppColors.gold),
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.45),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.gold : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiLuxBorderPainter extends CustomPainter {
  final Color accent;
  _KpiLuxBorderPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(.08);
    canvas.drawRRect(r.deflate(1), inner);

    final topLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        colors: [
          accent.withOpacity(.0),
          accent.withOpacity(.55),
          accent.withOpacity(.0),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, 10));

    final path = Path()
      ..moveTo(18, 6)
      ..lineTo(size.width - 18, 6);

    canvas.drawPath(path, topLine);
  }

  @override
  bool shouldRepaint(covariant _KpiLuxBorderPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
