import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/user_provider.dart';
import '../themes/app_theme.dart';
import 'dart:math' as math; // AppColors.gold

// ---- Config clé Google (évite le hardcode; fallback si non fournie) ----
const String kGooglePlacesApiKey = String.fromEnvironment(
  'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI',
  defaultValue: 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI',
);

Future<void> performLogout(BuildContext context) async {
  final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            "Confirmation",
            style: TextStyle(
              color: AppColors.gold,
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            "Souhaitez-vous vraiment vous déconnecter ?",
            style:
                TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            _LuxGhostButton(
              label: "Annuler",
              compact: true,
              onTap: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            ),
            const SizedBox(width: 10),
            _LuxDangerButton(
              label: "Se déconnecter",
              compact: true,
              onTap: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirm) return;

  try {
    await FirebaseAuth.instance.signOut();
    Provider.of<UserProvider>(context, listen: false).logout();

    if (context.mounted) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (context.mounted) GoRouter.of(context).go('/login');
      });
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text("Erreur lors de la déconnexion : $e",
            style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

// --- Réputation passager (top-level) ---
class _Reputation {
  final double avg; // moyenne des notes
  final int satisfied; // chauffeurs uniques satisfaits (>=4)
  final int total; // chauffeurs uniques totaux
  final List<Map<String, dynamic>> reviews;
  final double respectPct; // % respect des trajets
  final String? lastDriverId; // dernier chauffeur
  final String? lastDriverName; // nom dernier chauffeur

  // Rang basé sur le nombre de trajets
  final int completedTrips; // nb "Terminée"
  final double totalSpend; // somme price
  final double progressToNext; // 0..1 progression vers prochain rang

  const _Reputation({
    required this.avg,
    required this.satisfied,
    required this.total,
    required this.reviews,
    required this.respectPct,
    required this.lastDriverId,
    required this.lastDriverName,
    required this.completedTrips,
    required this.totalSpend,
    required this.progressToNext,
  });
}

// ---- Simple Shimmer sans package ----
class _Shimmer extends StatefulWidget {
  final double height;
  final double width;
  final BorderRadius radius;
  const _Shimmer({
    required this.height,
    this.width = double.infinity,
    this.radius = const BorderRadius.all(Radius.circular(16)),
  });
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

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
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _c.value, 0),
              end: Alignment(1 + 2 * _c.value, 0),
              colors: [Colors.grey[850]!, Colors.grey[800]!, Colors.grey[850]!],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// =====================
// UTILITAIRES PREMIUM
// =====================

class _WeatherPalette {
  final Color ringStart, ringEnd, glow, chipBg, chipText;
  const _WeatherPalette({
    required this.ringStart,
    required this.ringEnd,
    required this.glow,
    required this.chipBg,
    required this.chipText,
  });
}

_WeatherPalette _paletteFor(int code) {
  if (code == 0) {
    return const _WeatherPalette(
      ringStart: Color(0xFFFFD700),
      ringEnd: Color(0xFFA87C00),
      glow: Color(0x33FFD700),
      chipBg: Color(0x26FFD700),
      chipText: AppColors.gold,
    );
  }
  if (code == 1 || code == 2 || code == 3) {
    return const _WeatherPalette(
      ringStart: Color(0xFFE6C200),
      ringEnd: Color(0xFF8FA0B5),
      glow: Color(0x338FA0B5),
      chipBg: Color(0x1A8FA0B5),
      chipText: Colors.white70,
    );
  }
  if (code == 45 || code == 48) {
    return const _WeatherPalette(
      ringStart: Color(0xFFBFC6D0),
      ringEnd: Color(0xFF6F7B88),
      glow: Color(0x336F7B88),
      chipBg: Color(0x1A6F7B88),
      chipText: Colors.white70,
    );
  }
  if ({51, 53, 55, 61, 63, 65, 80, 81, 82}.contains(code)) {
    return const _WeatherPalette(
      ringStart: Color(0xFF50C2FF),
      ringEnd: Color(0xFF2A6FB8),
      glow: Color(0x332A6FB8),
      chipBg: Color(0x1A2A6FB8),
      chipText: Colors.white70,
    );
  }
  if ({66, 67, 71, 73, 75, 77, 85, 86}.contains(code)) {
    return const _WeatherPalette(
      ringStart: Color(0xFFB5E8FF),
      ringEnd: Color(0xFF6EC1E4),
      glow: Color(0x336EC1E4),
      chipBg: Color(0x1A6EC1E4),
      chipText: Colors.white70,
    );
  }
  if ({95, 96, 99}.contains(code)) {
    return const _WeatherPalette(
      ringStart: Color(0xFFFFD700),
      ringEnd: Color(0xFF6A5ACD),
      glow: Color(0x336A5ACD),
      chipBg: Color(0x1A6A5ACD),
      chipText: Colors.white70,
    );
  }
  return const _WeatherPalette(
    ringStart: Color(0xFFE6C200),
    ringEnd: Color(0xFF8FA0B5),
    glow: Color(0x338FA0B5),
    chipBg: Color(0x1A8FA0B5),
    chipText: Colors.white70,
  );
}

// ——— Bordure dégradée animée (carte luxe)
class _AnimatedLuxBorder extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final double radius;
  final double stroke;
  const _AnimatedLuxBorder({
    super.key,
    required this.child,
    required this.colors,
    this.radius = 16,
    this.stroke = 1.2,
  });

  @override
  State<_AnimatedLuxBorder> createState() => _AnimatedLuxBorderState();
}

class _AnimatedLuxBorderState extends State<_AnimatedLuxBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

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
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: SweepGradient(
              startAngle: _c.value * 6.2831853,
              endAngle: _c.value * 6.2831853 + 6.2831853,
              colors: [
                ...widget.colors,
                widget.colors.first,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Container(
            margin: EdgeInsets.all(widget.stroke),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(widget.radius - widget.stroke),
              color: Colors.grey[900],
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 12,
                    offset: Offset(3, 5)),
                BoxShadow(
                    color: Color(0x19000000),
                    blurRadius: 18,
                    offset: Offset(-3, -2)),
              ],
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ——— Icône anneau premium (animé)
class _LuxWeatherIcon extends StatefulWidget {
  final IconData icon;
  final int code;
  final double size;
  final double thickness;
  const _LuxWeatherIcon({
    super.key,
    required this.icon,
    required this.code,
    this.size = 56,
    this.thickness = 4,
  });

  @override
  State<_LuxWeatherIcon> createState() => _LuxWeatherIconState();
}

class _LuxWeatherIconState extends State<_LuxWeatherIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _paletteFor(widget.code);
    final r = widget.size;
    final inner = r - widget.thickness * 2;

    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // halo
            Container(
              width: r + 16,
              height: r + 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: p.glow, blurRadius: 26, spreadRadius: 2),
                ],
              ),
            ),
            // anneau
            Transform.rotate(
              angle: _c.value * 6.2831853,
              child: Container(
                width: r,
                height: r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [p.ringStart, p.ringEnd, p.ringStart],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            // masque intérieur (verre fumé)
            Container(
              width: inner,
              height: inner,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10, width: 1),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(3, 3)),
                  BoxShadow(
                      color: Color(0x19FFFFFF),
                      blurRadius: 10,
                      offset: Offset(-3, -3)),
                ],
              ),
            ),
            // lustre
            Positioned(
              top: 4,
              child: Container(
                width: inner * 0.88,
                height: inner * 0.46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22FFFFFF), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            Icon(widget.icon, size: inner * 0.56, color: Colors.white),
          ],
        );
      },
    );
  }
}

// ——— Chip “condition” luxe
class _ConditionChip extends StatelessWidget {
  final String label;
  final _WeatherPalette palette;
  const _ConditionChip({super.key, required this.label, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.chipText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}

// ——— Ligne métrique (icône + valeurs)
class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String hint;
  const _Metric({
    super.key,
    required this.icon,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white60),
        const SizedBox(width: 6),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, fontFamily: 'PlayfairDisplay'),
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '  '),
              TextSpan(
                text: hint,
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ————————— LUX HELPERS —————————

class _LuxMiniIcon extends StatelessWidget {
  final IconData icon;
  final Color ringStart;
  final Color ringEnd;
  final Color glow;
  final double size; // outer diameter

  const _LuxMiniIcon({
    super.key,
    required this.icon,
    required this.ringStart,
    required this.ringEnd,
    required this.glow,
    this.size = 32,
  });

  factory _LuxMiniIcon.danger({required IconData icon}) => _LuxMiniIcon(
        icon: icon,
        ringStart: const Color(0xFFFF5A5A),
        ringEnd: const Color(0xFFD24545),
        glow: const Color(0x33FF5A5A),
        size: 32,
      );

  factory _LuxMiniIcon.gold({required IconData icon}) => _LuxMiniIcon(
        icon: icon,
        ringStart: const Color(0xFFFFD700),
        ringEnd: const Color(0xFFA87C00),
        glow: const Color(0x33FFD700),
        size: 36,
      );

  @override
  Widget build(BuildContext context) {
    final inner = size - 6;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size + 8,
          height: size + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: glow, blurRadius: 16, spreadRadius: 1)
            ],
          ),
        ),
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [ringStart, ringEnd, ringStart],
              stops: const [0.0, .7, 1.0],
            ),
          ),
        ),
        Container(
          width: inner,
          height: inner,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white12, width: 1),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(2, 2)),
              BoxShadow(
                  color: Color(0x19FFFFFF),
                  blurRadius: 8,
                  offset: Offset(-2, -2)),
            ],
          ),
          child: Icon(icon, size: inner * .55, color: Colors.white),
        ),
      ],
    );
  }
}

// Préfixe luxe pour les TextFields (utilisé dans _inputDecoration, même nom conservé)
class _LuxPrefixIcon extends StatelessWidget {
  final IconData icon;
  const _LuxPrefixIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: _LuxMiniIcon.gold(icon: icon),
    );
  }
}

// Bouton “Activer” premium (pill gradient)
class _LuxActionPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _LuxActionPill({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = danger
        ? const [Color(0xFFFF6B6B), Color(0xFFD24545)]
        : const [Color(0xFFFFD700), Color(0xFFA87C00)];
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
                color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: danger ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  String _hintFrom = "Détection en cours...";
  List<Map<String, dynamic>> _trips = [];
  Map<String, dynamic>? _weather;
  bool _weatherLoading = false;
  final GlobalKey _trafficMapKey = GlobalKey();
  LatLng? _currentPosition;
  BitmapDescriptor? _customPassengerIcon;

  // Quick places (Maison/Travail/Aéroports)
  List<Map<String, String>> _quickPlaces = [];

  // Destinations récentes (local)
  List<String> _recentDestinations = [];

  // Navigation guard
  bool _isNavigating = false;

  // Grille des rangs PAR NOMBRE DE TRAJETS
  static const int bronzeMin = 1; // >=1
  static const int argentMin = 100; // suggestion
  static const int orMin = 250; // ✅ Or à 250
  static const int diamantMin = 500; // ✅ Diamant à 500

  @override
  void initState() {
    super.initState();
    _initIntl();
    _detectCurrentLocation();
    _loadTrips();
    _loadQuickPlaces();
    _loadRecentDestinations();
    _initWeather();
    _initTrafficAssets();
    _ensureCurrentLatLng();
  }

  void _initIntl() {
    // Assure le locale fr pour les formats de date
    Intl.defaultLocale = 'fr_FR';
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String _rankFromTrips(int trips) {
    if (trips >= diamantMin) return "Voyageur Diamant";
    if (trips >= orMin) return "Voyageur d'Or";
    if (trips >= argentMin) return "Voyageur d'Argent";
    if (trips >= bronzeMin) return "Voyageur de Bronze";
    return "—";
  }

  double _progressToNextByTrips(int trips) {
    // Diamant atteint → 100 %
    if (trips >= diamantMin) return 1.0;

    int currentFloor, nextFloor;
    if (trips >= orMin) {
      currentFloor = orMin;
      nextFloor = diamantMin; // Or → Diamant
    } else if (trips >= argentMin) {
      currentFloor = argentMin;
      nextFloor = orMin; // Argent → Or
    } else if (trips >= bronzeMin) {
      currentFloor = bronzeMin;
      nextFloor = argentMin; // Bronze → Argent
    } else {
      currentFloor = 0;
      nextFloor = bronzeMin; // Vers Bronze
    }

    final span = (nextFloor - currentFloor).toDouble();
    final done = (trips - currentFloor).toDouble().clamp(0.0, span);
    final p = span == 0 ? 0.0 : (done / span);
    return p; // 0..1
  }

  String _nextRankFromTrips(int trips) {
    if (trips >= diamantMin) return "Rang max";
    if (trips >= orMin) return "Voyageur Diamant";
    if (trips >= argentMin) return "Voyageur d'Or";
    if (trips >= bronzeMin) return "Voyageur d'Argent";
    return "Voyageur de Bronze";
  }

  String _gaugeBottomLabelForTrips(int trips) {
    final n = _nextRankFromTrips(trips);
    return (n == "Rang max") ? "Atteint" : "vers ${n.split(' ').last}";
  }

  Future<bool?> _confirmLogout(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          "Déconnexion",
          style: TextStyle(
            color: AppColors.gold,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "Souhaitez-vous vraiment vous déconnecter ?",
          style:
              TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          _LuxGhostButton(
            label: "Annuler",
            compact: true,
            onTap: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(width: 10),
          _LuxDangerButton(
            label: "Se déconnecter",
            onTap: () => performLogout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _initTrafficAssets() async {
    try {
      _customPassengerIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        'assets/icons/car_gold.png', // change le chemin si besoin
      );
      if (mounted) setState(() {});
    } catch (_) {
      // fallback: laisser null → defaultMarker
    }
  }

  Future<void> _ensureCurrentLatLng() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
      });
    } catch (_) {
      // silencieux
    }
  }

  Future<void> _initWeather() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
    }
    await _loadWeather();
  }

  Future<void> _loadTrips() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .get();

    if (!mounted) return;

    final now = DateTime.now();

    final upcoming = snapshot.docs
        .where((doc) => (doc['timestamp'] as Timestamp).toDate().isAfter(now))
        .toList()
      ..sort((a, b) =>
          (a['timestamp'] as Timestamp).compareTo(b['timestamp'] as Timestamp));

    final past = snapshot.docs
        .where((doc) => (doc['timestamp'] as Timestamp).toDate().isBefore(now))
        .toList()
      ..sort((a, b) =>
          (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

    setState(() {
      _trips = [
        if (upcoming.isNotEmpty)
          {
            "title": "Prochain trajet",
            "from": upcoming.first['from'],
            "to": upcoming.first['to'],
            "date": _formatDate(upcoming.first['timestamp']),
          },
        if (past.isNotEmpty)
          {
            "title": "Dernier trajet",
            "from": past.first['from'],
            "to": past.first['to'],
            "date": _formatDate(past.first['timestamp']),
          },
        {
          "title": "Voir tous mes trajets",
          "from": "",
          "to": "",
          "date": "",
        },
      ];
    });
  }

  // Quick places facultatifs: users/{uid}/places (label, address)
  Future<void> _loadQuickPlaces() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('places')
          .get();

      if (!mounted) return;

      final items = snap.docs
          .map((d) {
            final m = d.data();
            final label = (m['label'] ?? '').toString();
            final address = (m['address'] ?? '').toString();
            if (label.isEmpty || address.isEmpty) return null;
            return {"label": label, "address": address};
          })
          .whereType<Map<String, String>>()
          .toList();

      setState(() => _quickPlaces = items.take(6).toList());
    } catch (_) {
      // silencieux -> rien à afficher
    }
  }

  // Historique local de 3 destinations
  Future<void> _loadRecentDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recent_destinations') ?? <String>[];
    if (!mounted) return;
    setState(() => _recentDestinations = list.take(3).toList());
  }

  Future<void> _saveRecentDestination(String dest) async {
    if (dest.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('recent_destinations') ?? <String>[];
    // place en tête, unicité
    list.remove(dest);
    list.insert(0, dest);
    await prefs.setStringList('recent_destinations', list.take(10).toList());
    if (!mounted) return;
    setState(() => _recentDestinations = list.take(3).toList());
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final f = DateFormat('EEE d MMM • HH:mm', 'fr_FR');
    return f.format(date);
  }

  Future<void> _detectCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS désactivé');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Permission refusée');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Permission permanente refusée');
      }

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      final city = placemarks.first.locality ??
          placemarks.first.administrativeArea ??
          "Votre position";

      if (!mounted) return;
      setState(() {
        _fromController.text = city;
        _hintFrom = city;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hintFrom = "Saisir votre point de départ";
      });
    }
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  // --------- UNIQUE: Fetch réputation (notes + trajets + progression) ----------
  Future<_Reputation> _fetchPassengerReputation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const _Reputation(
        avg: 0.0,
        satisfied: 0,
        total: 0,
        reviews: [],
        respectPct: 0.0,
        lastDriverId: null,
        lastDriverName: null,
        completedTrips: 0,
        totalSpend: 0.0,
        progressToNext: 0.0,
      );
    }

    // ---------- A) FEEDBACKS CHAUFFEURS ----------
    // On charge assez large pour les stats uniques, mais
    // on fournira au carrousel uniquement les 10 plus récents.
    final fbSnap = await FirebaseFirestore.instance
        .collection('feedbacks')
        .where('passengerId', isEqualTo: uid)
        .where('fromDriver', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(100) // marge pour stats uniques
        .get();

    // Liste brute ordonnée (DESC)
    final List<Map<String, dynamic>> allReviews = fbSnap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      // Ajoute un id stable pour stabiliser l’UI (PageView key)
      data['reviewId'] = d.id;
      return data;
    }).toList();

    // ✅ 10 derniers avis pour l’UI (carrousel)
    final List<Map<String, dynamic>> reviewsForUi =
        allReviews.take(10).toList();

    // ✅ Stats sur le dernier avis de chaque chauffeur (unicité par driverId)
    final Map<String, Map<String, dynamic>> latestByDriver = {};
    for (final r in allReviews) {
      final driverId = (r['driverId'] ?? '').toString();
      if (driverId.isEmpty) continue;
      // allReviews est déjà trié DESC → le premier rencontré est le plus récent
      latestByDriver.putIfAbsent(driverId, () => r);
    }
    final List<Map<String, dynamic>> uniqueLatest =
        latestByDriver.values.toList();

    // Moyenne (sur derniers avis par chauffeur)
    final int totalUnique = uniqueLatest.length;
    final double sumAvg = uniqueLatest.fold<double>(
      0.0,
      (s, r) => s + ((r['rating'] ?? 0) as num).toDouble(),
    );
    final double avg = totalUnique == 0 ? 0.0 : (sumAvg / totalUnique);

    // Chauffeurs satisfaits (notation >= 4)
    final int satisfied = uniqueLatest.where((r) {
      final rating = ((r['rating'] ?? 0) as num).toDouble();
      return rating >= 4.0;
    }).length;

    // ---------- B) RÉSERVATIONS (respect%, trajets, dépenses, dernier chauffeur) ----------
    final resSnap = await FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: uid)
        .get();

    int completed = 0;
    int canceledByPassenger = 0;
    double totalSpend = 0.0;
    Map<String, dynamic>? lastResData;
    DateTime? lastResDate;

    bool isCanceledByPassenger(Map<String, dynamic> data) {
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (!status.contains('annul')) return false;
      final by =
          (data['canceledBy'] ?? data['cancelledBy'] ?? data['cancelBy'] ?? '')
              .toString()
              .toLowerCase();
      return by.contains('passager') ||
          by.contains('passenger') ||
          by.contains('user') ||
          by.contains('client');
    }

    DateTime? _extractDate(Map<String, dynamic> m) {
      final v =
          m['timestamp'] ?? m['endTime'] ?? m['startTime'] ?? m['createdAt'];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    for (final d in resSnap.docs) {
      final data = d.data();
      final s = (data['status'] ?? '').toString().toLowerCase();

      if (s.contains('termin')) {
        completed++;
        totalSpend += ((data['price'] ?? 0) as num).toDouble();
      } else if (isCanceledByPassenger(data)) {
        canceledByPassenger++;
      }

      final dt = _extractDate(data);
      if (dt != null && (lastResDate == null || dt.isAfter(lastResDate!))) {
        lastResDate = dt;
        lastResData = data;
      }
    }

    final int denom = completed + canceledByPassenger;
    final double respectPct = denom == 0 ? 100.0 : (completed / denom) * 100.0;

    final String? lastDriverId =
        lastResData != null ? (lastResData!['driverId'] as String?) : null;
    final String? lastDriverName =
        lastResData != null ? (lastResData!['driverName'] as String?) : null;

    // ---------- C) PROGRESSION RANG ----------
    final double progressToNext = _progressToNextByTrips(completed);

    // ---------- D) RETOUR ----------
    return _Reputation(
      avg: (avg.isNaN || !avg.isFinite) ? 0.0 : avg,
      satisfied: satisfied,
      total: totalUnique,
      reviews: reviewsForUi, // ✅ 10 derniers pour l’UI
      respectPct: (respectPct.isNaN || !respectPct.isFinite) ? 0.0 : respectPct,
      lastDriverId: lastDriverId,
      lastDriverName: lastDriverName,
      completedTrips: completed,
      totalSpend: totalSpend,
      progressToNext: (progressToNext.isNaN || !progressToNext.isFinite)
          ? 0.0
          : progressToNext,
    );
  }

  // -------------------- UI utilitaires --------------------

  Future<void> _loadWeather() async {
    try {
      setState(() => _weatherLoading = true);

      // utilise la même permission que la détection de ville
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${pos.latitude}&longitude=${pos.longitude}'
        '&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
      );

      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final cur = (j['current'] as Map?) ?? {};
        if (!mounted) return;
        setState(() {
          _weather = {
            't': (cur['temperature_2m'] ?? 0).toDouble(),
            'feels': (cur['apparent_temperature'] ?? 0).toDouble(),
            'code': (cur['weather_code'] ?? -1).toInt(),
            'wind': (cur['wind_speed_10m'] ?? 0).toDouble(),
          };
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _weather = null);
    } finally {
      if (!mounted) return;
      setState(() => _weatherLoading = false);
    }
  }

  String _wmoLabel(int code) {
    switch (code) {
      case 0:
        return "Ciel clair";
      case 1:
      case 2:
        return "Partiellement nuageux";
      case 3:
        return "Couvert";
      case 45:
      case 48:
        return "Brouillard";
      case 51:
      case 53:
      case 55:
        return "Bruine";
      case 61:
      case 63:
      case 65:
        return "Pluie";
      case 66:
      case 67:
        return "Pluie verglaçante";
      case 71:
      case 73:
      case 75:
        return "Neige";
      case 77:
        return "Grésil";
      case 80:
      case 81:
      case 82:
        return "Averses";
      case 85:
      case 86:
        return "Averses de neige";
      case 95:
        return "Orage";
      case 96:
      case 99:
        return "Orage violent";
      default:
        return "Météo";
    }
  }

  IconData _wmoIcon(int code) {
    switch (code) {
      case 0:
        return Icons.wb_sunny_rounded;
      case 1:
      case 2:
        return Icons.wb_cloudy_rounded;
      case 3:
        return Icons.cloud_rounded;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
      case 61:
      case 63:
      case 65:
      case 80:
      case 81:
      case 82:
        return Icons.umbrella_rounded;
      case 66:
      case 67:
        return Icons.ac_unit_rounded;
      case 71:
      case 73:
      case 75:
      case 85:
      case 86:
        return Icons.ac_unit_rounded;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm_rounded;
      default:
        return Icons.wb_cloudy_rounded;
    }
  }

  Widget _weatherSection() {
    if (_weatherLoading) return const _Shimmer(height: 86);
    if (_weather == null) return const SizedBox.shrink();

    final t = (_weather!['t'] as double).toStringAsFixed(1);
    final feels = (_weather!['feels'] as double).toStringAsFixed(1);
    final wind = (_weather!['wind'] as double).toStringAsFixed(0);
    final code = _weather!['code'] as int;

    final palette = _paletteFor(code);
    final condition = _wmoLabel(code);
    final isClear = code == 0;

    final screenW = MediaQuery.sizeOf(context).width;
    final isNarrow = screenW < 380; // web mobile étroit / petits devices

    return _AnimatedLuxBorder(
      colors: [palette.ringStart, palette.ringEnd],
      radius: 18,
      stroke: 1.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icône météo (un peu plus petit si étroit)
            _LuxWeatherIcon(
              icon: _wmoIcon(code),
              code: code,
              size: isNarrow ? 48 : 56,
              thickness: 4,
            ),
            const SizedBox(width: 12),

            // Infos (titre + métriques)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre seul (plus de chip => pas de doublon)
                  Text(
                    condition,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isClear ? AppColors.gold : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: isNarrow ? 14 : 15,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Métriques : Wrap pour autoriser le retour ligne si très serré
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _Metric(
                        icon: Icons.thermostat_rounded,
                        value: "$feels°",
                        hint: "Ressenti",
                      ),
                      _Metric(
                        icon: Icons.air_rounded,
                        value: "$wind km/h",
                        hint: "Vent",
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Température principale : compressible, jamais d’overflow
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: RichText(
                  text: TextSpan(
                    text: t,
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: isNarrow ? 22 : 24,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'PlayfairDisplay',
                    ),
                    children: const [
                      TextSpan(
                        text: "°",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reputationCard(_Reputation rep) {
    // Safeguards
    final double avgRaw = (rep.avg ?? 0).toDouble();
    final double avg = (avgRaw.isNaN || !avgRaw.isFinite) ? 0 : avgRaw;

    final double respectRaw = (rep.respectPct ?? 0).toDouble();
    final int respect =
        (respectRaw.isNaN || !respectRaw.isFinite) ? 0 : respectRaw.round();

    final int satisfied = rep.satisfied ?? 0;
    final int total = rep.total ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 20),
            SizedBox(width: 8),
            Text(
              "Voyageur d'excellence",
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _repRow("Note globale", "⭐ ${avg.toStringAsFixed(1)} / 5"),
          _repRow("Distinction", _safeMedalFrom(avg)),
          _repRow("Respect des trajets", "$respect %"),
          _repRow("Chauffeurs satisfaits", "$satisfied / $total"),
        ],
      ),
    );
  }

// Version "safe" de la médaille
  String _safeMedalFrom(double avg) {
    if (avg.isNaN || !avg.isFinite) return "—";
    if (avg >= 4.8) return "Voyageur Diamant";
    if (avg >= 4.5) return "Voyageur d'Or";
    if (avg >= 4.0) return "Voyageur d'Argent";
    if (avg >= 3.5) return "Voyageur de Bronze";
    return "En progression";
  }

// Si tu as un calcul côté modèle, blinde-le aussi :
  double computeAverageRating(List<num>? ratings) {
    final list = ratings ?? const [];
    if (list.isEmpty) return 0;
    final sum = list.fold<double>(0, (a, b) => a + b.toDouble());
    final avg = sum / list.length;
    return (avg.isNaN || !avg.isFinite) ? 0 : avg;
  }

  double computeRespectPct(int onTime, int total) {
    if (total <= 0) return 0;
    final pct = (onTime / total) * 100.0;
    return (pct.isNaN || !pct.isFinite) ? 0 : pct;
  }

  Widget _repRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                flex: 4,
                child:
                    Text(label, style: const TextStyle(color: Colors.white70))),
            Expanded(
              flex: 6,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: AppColors.gold, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _reviewsCarousel(List<Map<String, dynamic>> reviews) {
    if (reviews.isEmpty) {
      return const Text(
        "Aucun avis de chauffeur pour le moment.",
        style: TextStyle(color: Colors.white38),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "📝 Avis des chauffeurs",
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: reviews.length,
            itemBuilder: (context, index) {
              final r = reviews[index];
              final rating = ((r['rating'] ?? 0) as num).toDouble();
              final comment = (r['comment'] ?? '') as String;
              final ts = r['timestamp'];
              final DateTime? date = (ts is Timestamp) ? ts.toDate() : null;
              final dateStr = date != null ? "• ${_frShortDate(date)}" : "";

              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _starRow(rating),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          comment,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(
                          dateStr,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _reputationFusion(_Reputation rep) {
    final rank = _rankFromTrips(rep.completedTrips);

    // Jauge safe
    final double gauge = (rep.progressToNext ?? 0).toDouble().clamp(0, 1);

    // Prochain rang
    final String next = _nextRankFromTrips(rep.completedTrips) ?? "";
    final String nextWord = () {
      final trimmed = next.trim();
      if (trimmed.isEmpty) return "prochain rang";
      final parts =
          trimmed.split(' ').where((s) => s.trim().isNotEmpty).toList();
      return parts.isEmpty ? trimmed : parts.last;
    }();

    // Palier
    int nextTarget;
    if (rank == "Voyageur Diamant") {
      nextTarget = diamantMin;
    } else if (rank == "Voyageur d'Or") {
      nextTarget = diamantMin;
    } else if (rank == "Voyageur d'Argent") {
      nextTarget = orMin;
    } else if (rank == "Voyageur de Bronze") {
      nextTarget = argentMin;
    } else {
      nextTarget = bronzeMin;
    }

    final currency = NumberFormat.currency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 0,
    );

    // ✅✅  TOP 10 AVIS TRIÉS DESC
    final List<Map<String, dynamic>> _reviewsProcessed = (() {
      final raw =
          (rep.reviews as List?)?.whereType<Map<String, dynamic>>().toList() ??
              const [];
      raw.sort((a, b) {
        final ta = a['timestamp'] as Timestamp?;
        final tb = b['timestamp'] as Timestamp?;
        final ma = ta?.millisecondsSinceEpoch ?? 0;
        final mb = tb?.millisecondsSinceEpoch ?? 0;
        return mb.compareTo(ma);
      });
      return raw.take(10).toList();
    })();

    return _AnimatedLuxBorder(
      colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
      radius: 22,
      stroke: 1.2,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ✅ HEADER
            Row(
              children: [
                _LuxMiniIcon.gold(icon: Icons.emoji_events_rounded),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Voyageur d'excellence",
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                ),
                _LuxGauge(
                  value: gauge.isNaN ? 0 : gauge,
                  top: "${((gauge.isNaN ? 0 : gauge) * 100).round()}%",
                  bottom: (next == "Voyageur Diamant")
                      ? "Rang max"
                      : "vers $nextWord",
                  size: 64,
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// ✅ KPI
            Column(
              children: [
                _InfoKPI(
                  icon: Icons.military_tech_rounded,
                  label: "Distinction",
                  value: rank.isEmpty ? "—" : rank,
                ),
                const SizedBox(height: 10),
                _InfoKPI(
                  icon: Icons.directions_car_filled_rounded,
                  label: "Trajets",
                  value: "${rep.completedTrips ?? 0}",
                ),
                const SizedBox(height: 10),
                _InfoKPI(
                  icon: Icons.verified_rounded,
                  label: "Respect trajets",
                  value:
                      "${(rep.respectPct ?? 0).isNaN ? 0 : (rep.respectPct ?? 0).round()} %",
                ),
                const SizedBox(height: 10),
                _InfoKPI(
                  icon: Icons.handshake_rounded,
                  label: "Chauffeurs satisfaits",
                  value: "${rep.satisfied ?? 0} / ${rep.total ?? 0}",
                ),
                const SizedBox(height: 10),
                _InfoKPI(
                  icon: Icons.account_balance_wallet_rounded,
                  label: "Cumul dépensé",
                  value: currency.format((rep.totalSpend ?? 0)),
                  compact: true,
                ),
              ],
            ),

            const SizedBox(height: 14),
            const SizedBox(height: 10),

            /// ✅ AVIS
            if (_reviewsProcessed.isEmpty)
              const Text(
                "Aucun avis de chauffeur pour le moment.",
                style: TextStyle(color: Colors.white38),
              )
            else
              SizedBox(
                height: 168,
                child: PageView.builder(
                  key: ValueKey(_reviewsProcessed
                      .map((r) => r['reviewId'] ?? r['timestamp'] ?? '')
                      .join(',')),
                  controller:
                      PageController(viewportFraction: 0.9, keepPage: false),
                  itemCount: _reviewsProcessed.length,
                  itemBuilder: (context, index) {
                    final r = _reviewsProcessed[index];
                    final rating = ((r['rating'] ?? 0) as num).toDouble();
                    final comment = (r['comment'] ?? '') as String;
                    final ts = r['timestamp'] as Timestamp?;
                    final dateStr = ts != null ? _frShortDate(ts.toDate()) : "";

                    return Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.gold.withOpacity(.25)),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.grey[900]!,
                            Colors.grey[900]!.withOpacity(.85),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withOpacity(0.10),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _starRow(rating),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              comment.trim().isEmpty ? "—" : "“ $comment ”",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              dateStr.isEmpty ? "" : "• $dateStr",
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(double value) {
    final v = value.clamp(0.0, 1.0);
    final minVisual = (v == 0.0) ? 0.03 : v; // 3 % mini
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: minVisual,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _fusionInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard({
    required Widget stars,
    required String comment,
    required String footer,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stars,
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              comment,
              style: const TextStyle(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              footer,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _starRow(double rating) {
    final full = rating.floor();
    final half = (rating - full) >= 0.5;
    final icons = <Widget>[];
    for (var i = 0; i < 5; i++) {
      if (i < full) {
        icons
            .add(const Icon(Icons.star_rounded, size: 16, color: Colors.amber));
      } else if (i == full && half) {
        icons.add(
            const Icon(Icons.star_half_rounded, size: 16, color: Colors.amber));
      } else {
        icons.add(const Icon(Icons.star_border_rounded,
            size: 16, color: Colors.amber));
      }
    }
    return Row(children: icons);
  }

  String _frShortDate(DateTime d) {
    const mois = [
      "",
      "janv.",
      "févr.",
      "mars",
      "avr.",
      "mai",
      "juin",
      "juil.",
      "août",
      "sept.",
      "oct.",
      "nov.",
      "déc."
    ];
    return "${d.day} ${mois[d.month]}";
  }

  static String _medalFrom(double avg) {
    if (avg >= 4.5) return "Voyageur d'Or";
    if (avg >= 3.5) return "Voyageur d'Argent";
    if (avg > 0) return "Voyageur de Bronze";
    return "—";
  }

  void _submitSearch() {
    if (_isNavigating) return;
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Merci de renseigner le départ et la destination"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    _isNavigating = true;
    HapticFeedback.lightImpact();
    _saveRecentDestination(to);
    context.go('/results?from=$from&to=$to');
    Future.delayed(const Duration(milliseconds: 600), () {
      _isNavigating = false;
    });
  }

  void _rebookLastTrip() {
    final last = _trips.firstWhere(
      (t) => t['title'] == 'Dernier trajet',
      orElse: () => {},
    );
    if (last.isEmpty) return;
    _fromController.text = last['from'] ?? '';
    _toController.text = last['to'] ?? '';
    _submitSearch();
  }

  // -------------------- BUILD --------------------
  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userName = userProvider.userName;
    final greeting = _getGreeting();
    final isSmall = MediaQuery.of(context).size.width < 370;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D0D0D), Color(0xFF1C1C1C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NEW (drop directly in the same place)
                  PremiumHeader(
                    greeting: greeting,
                    userName: userName,
                    onProfile: () => context.go('/profile'),
                  ),
                  const SizedBox(height: 8),
                  FadeInRight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                            ).createShader(bounds);
                          },
                        ),
                        const SizedBox(height: 12),
                        _weatherSection(),
                        const SizedBox(height: 6),

                        TrafficPanelPremium(
                          center: _currentPosition,
                          markers: {
                            if (_currentPosition != null)
                              Marker(
                                markerId: const MarkerId("passenger"),
                                position: _currentPosition!,
                                icon: _customPassengerIcon ??
                                    BitmapDescriptor.defaultMarker,
                              ),
                          },
                          hasIncidents: false,
                          onTapVoir: () {
                            final ctx = _trafficMapKey.currentContext;
                            if (ctx != null) {
                              Scrollable.ensureVisible(
                                ctx,
                                duration: const Duration(milliseconds: 480),
                                curve: Curves.easeOutCubic,
                                alignment: .05,
                              );
                            }
                          },
                        ),

//

// --- Texte + ligne animée ---
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Texte premium avec dégradé or
                              ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFA87C00)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds),
                                child: const Text(
                                  "Préparez-vous à vivre un trajet d’exception. ✨",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    fontFamily: 'PlayfairDisplay',
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Color(0xAA000000),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Ligne animée élégante
                              _GoldLine(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Si GPS off/perms refusées -> info discrète
                  if (_hintFrom == "Saisir votre point de départ")
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          _LuxMiniIcon.danger(icon: Icons.location_off),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Activez la localisation pour détecter votre ville automatiquement.",
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          _LuxActionPill(
                            label: "Activer",
                            onTap: _openLocationSettings,
                            danger: true,
                          ),
                        ],
                      ),
                    ),

                  // Champ départ
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _fromController,
                    googleAPIKey: kGooglePlacesApiKey,
                    debounceTime: 800,
                    countries: const ["fr"],
                    fetchCoordinates: true,
                    style: const TextStyle(color: Colors.white),
                    decoration:
                        _inputDecoration(_hintFrom, Icons.place_rounded),
                    onSuggestionClicked: (prediction) {
                      _fromController.text = prediction.description!;
                      FocusScope.of(context).unfocus();
                    },
                    overlayContainerBuilder: (child) => Material(
                      elevation: 2.0,
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Chips rapides (facultatifs)
                  _quickPlaces.isEmpty
                      ? const SizedBox.shrink()
                      : _quickPlacesChips(),

                  // Historique destinations récentes (facultatif)
                  _recentDestinations.isEmpty
                      ? const SizedBox.shrink()
                      : _recentRow(),

                  const SizedBox(height: 8),

                  // Champ destination
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _toController,
                    googleAPIKey: kGooglePlacesApiKey,
                    debounceTime: 800,
                    countries: const ["fr"],
                    fetchCoordinates: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                        "Entrer une destination", Icons.flag_rounded),
                    onSuggestionClicked: (prediction) {
                      _toController.text = prediction.description!;
                      _saveRecentDestination(prediction.description!);
                      FocusScope.of(context).unfocus();
                    },
                    onEditingComplete: _submitSearch,
                    overlayContainerBuilder: (child) => Material(
                      elevation: 2.0,
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bouton rechercher
                  Semantics(
                    button: true,
                    label: 'Trouver un véhicule',
                    child: InkWell(
                      onTap: _submitSearch,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Text(
                              "Trouver un véhicule",
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'PlayfairDisplay',
                              ),
                            ),
                            Positioned(
                              right: 16,
                              child: Icon(
                                Icons
                                    .arrow_forward_rounded, // ou Icons.directions_car_rounded
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  _homeButton(context, Icons.event_note, "Mes réservations",
                      '/reservations'),
                  _homeButton(context, Icons.favorite_border, "Mes favoris",
                      '/favorites'),

                  // Carrousel trajets (Shimmer/Empty states élégants)
                  if (_trips.isEmpty) ...[
                    const _Shimmer(height: 160),
                    const SizedBox(height: 8),
                    _emptyTripsCard(),
                  ] else
                    Column(
                      children: [
                        SizedBox(
                          height: isSmall ? 210 : 224,
                          child: PageView.builder(
                            controller: _pageController,
                            padEnds: false,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _trips.length,
                            itemBuilder: (context, index) {
                              final trip = _trips[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 12.0),
                                child: _TripCard(
                                  title: trip['title'],
                                  from: trip['from'],
                                  to: trip['to'],
                                  date: trip['date'],
                                  onRebook: _rebookLastTrip,
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ✅ Indicateurs animés sans rebuild global
                        AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, _) {
                            final hasClients = _pageController.hasClients;
                            final double? rawPage =
                                hasClients ? _pageController.page : 0;
                            final int current = rawPage?.round() ?? 0;

                            return Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 6,
                              children: List.generate(
                                _trips.length,
                                (index) => _buildDot(index == current),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                  const SizedBox(height: 28),

                  // Réputation (Shimmer -> FutureBuilder)
                  FutureBuilder<_Reputation>(
                    future: _fetchPassengerReputation(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const _Shimmer(height: 260);
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: CircularProgressIndicator(
                                color: AppColors.gold),
                          ),
                        );
                      }
                      final rep = snap.data!;
                      final rank = _rankFromTrips(rep.completedTrips);

                      // --- Message personnalisé selon le rang ---
                      String message;
                      switch (rank) {
                        case "Voyageur Diamant":
                          message =
                              "Vous êtes au sommet, voyageur d’exception 💎";
                          break;
                        case "Voyageur d'Or":
                          message =
                              "Élégance et fidélité : vous brillez parmi les voyageurs d’Or ✨";
                          break;
                        case "Voyageur d'Argent":
                          message =
                              "Toujours plus haut ! Votre parcours inspire confiance 🥈";
                          break;
                        case "Voyageur de Bronze":
                          message =
                              "Chaque trajet compte : votre aventure commence 🥉";
                          break;
                        default:
                          message = "Bienvenue dans l’univers Ride My Way ✨";
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color.fromARGB(255, 255, 255, 255),
                                fontSize: 16,
                                fontFamily: 'PlayfairDisplay',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _reputationFusion(
                              rep), // <-- Statistiques "Voyageur d'excellence"
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),
                  Center(
                    child: _LuxDangerButton(
                      label: "Se déconnecter",
                      onTap: () => performLogout(context),
                    ),
                  ),
                  const SizedBox(height: 40),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickPlacesChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _quickPlaces.map((p) {
          return ChoiceChip(
            label:
                Text(p['label']!, style: const TextStyle(color: Colors.black)),
            selected: false,
            onSelected: (_) {
              _toController.text = p['address']!;
              _saveRecentDestination(p['address']!);
              FocusScope.of(context).unfocus();
            },
            backgroundColor: const Color(0xFFFFD700),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          );
        }).toList(),
      ),
    );
  }

  Widget _recentRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.history, color: Colors.white54, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _recentDestinations.map((d) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label:
                          Text(d, style: const TextStyle(color: Colors.white)),
                      onPressed: () {
                        _toController.text = d;
                        _submitSearch();
                      },
                      backgroundColor: Colors.grey[850],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTripsCard() {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.directions_car, color: AppColors.gold),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Réservez votre premier trajet ✨",
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
            ),
            TextButton(
              onPressed: _submitSearch,
              child: const Text("Chercher",
                  style: TextStyle(color: AppColors.gold)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
      filled: true,
      fillColor: Colors.grey[900],
      // — premium prefix (garde la signature existante)
      prefixIcon: _LuxPrefixIcon(icon: icon),
      prefixIconConstraints: const BoxConstraints(minWidth: 56, minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.gold, width: 1.4),
      ),
    );
  }

  Widget _homeButton(
    BuildContext context,
    IconData icon,
    String label,
    String route,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _HomeButtonPremium(
        icon: icon,
        label: label,
        onTap: () => context.go(route),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 16 : 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.gold : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final String title;
  final String from;
  final String to;
  final String date;
  final VoidCallback? onRebook;

  const _TripCard({
    required this.title,
    required this.from,
    required this.to,
    required this.date,
    this.onRebook,
  });

  bool get _isRedirect => from.isEmpty && to.isEmpty;
  bool get _isLastTrip => title == 'Dernier trajet';

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 370; // mode compact pour petits écrans

    if (_isRedirect) {
      // --- Carte "Voir tous mes trajets" ---
      return _AnimatedLuxBorder(
        colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
        radius: 16,
        stroke: 1.1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/reservations'),
          child: Container(
            padding: EdgeInsets.all(compact ? 14 : 16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _LuxMiniIcon.gold(icon: Icons.directions_car_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Voir tous mes trajets",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 15 : 16,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // --- Carte trajet premium ---
    return _AnimatedLuxBorder(
      colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
      radius: 16,
      stroke: 1.1,
      child: Container(
        padding: EdgeInsets.all(compact ? 14 : 16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // évite l’overflow vertical
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre + date
            Row(
              children: [
                _LuxMiniIcon.gold(icon: Icons.star_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 12 : 13,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _DatePill(text: date, compact: compact),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),

            // FROM
            Row(
              children: [
                const Icon(Icons.fmd_good_rounded,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // séparateur doré + flèche
            Row(
              children: [
                Expanded(child: _goldLine(margin: compact ? 18 : 22)),
                Icon(Icons.arrow_forward_rounded,
                    color: AppColors.gold, size: compact ? 16 : 18),
                Expanded(child: _goldLine(margin: compact ? 18 : 22)),
              ],
            ),
            const SizedBox(height: 6),

            // TO
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    to,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

// CTA “Refaire ce trajet”  (never overflows)
            if (_isLastTrip && onRebook != null) ...[
              SizedBox(height: compact ? 6 : 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // FittedBox lets the pill scale down if space is tight
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _LuxCta(
                        icon: Icons.refresh_rounded,
                        // shorter label on very small screens
                        label: compact ? "Refaire" : "Refaire ce trajet",
                        onTap: onRebook!,
                        compact: compact,
                      ),
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}

// ——— Helpers ———

Widget _goldLine({required double margin}) => Container(
      height: 1,
      margin: EdgeInsets.symmetric(horizontal: margin),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x22FFD700), Color(0x44FFD700), Color(0x22FFD700)],
        ),
      ),
    );

class _DatePill extends StatelessWidget {
  final String text;
  final bool compact;
  const _DatePill({required this.text, this.compact = false});
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withOpacity(0.06), Colors.black12],
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 11 : 12,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ),
    );
  }
}

/// Bouton pill premium (doré) pour les actions
class _LuxCta extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _LuxCta({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // largeur cible (plus long) mais restera compressible via FittedBox parent
    final minW = compact ? 140.0 : 200.0;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minW),
        child: Container(
          alignment: Alignment.center, // texte centré quand la largeur augmente
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18, // un peu plus large
            vertical: compact ? 7 : 10,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.black, size: compact ? 16 : 18),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeButtonPremium extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HomeButtonPremium({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HomeButtonPremium> createState() => _HomeButtonPremiumState();
}

class _HomeButtonPremiumState extends State<_HomeButtonPremium>
    with SingleTickerProviderStateMixin {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return _AnimatedLuxBorder(
      colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
      radius: 16,
      stroke: 1.1,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _down ? 0.985 : 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onHighlightChanged: (v) => setState(() => _down = v),
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icône anneau doré
                _LuxMiniIcon.gold(icon: widget.icon),
                const SizedBox(width: 12),

                // Libellé
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Pastille “verre fumé” + chevron
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white.withOpacity(0.06), Colors.black12],
                    ),
                    border: Border.all(color: Colors.white10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(2, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} // AppColors.gold

// Jauge circulaire premium (verre fumé + dégradé or + cap arrondi)
class _LuxGauge extends StatelessWidget {
  final double value; // 0..1
  final String top; // ex: "16%"
  final String bottom; // ex: "vers d'Argent"
  final double size;

  const _LuxGauge({
    super.key,
    required this.value,
    required this.top,
    required this.bottom,
    this.size = 64, // un peu plus grand pour la lisibilité
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo doux autour de l’anneau
          Container(
            width: size + 14,
            height: size + 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withOpacity(.12),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),

          // Piste + arc
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(v),
          ),

          // Pastille “verre fumé” intérieure
          Container(
            width: size - 12,
            height: size - 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(.06),
                  Colors.black12,
                ],
              ),
              border: Border.all(color: Colors.white10),
            ),
          ),

          // Texte centre (s’adapte, jamais d’overflow)
          SizedBox(
            width: size * .72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    top,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'PlayfairDisplay',
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bottom,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'PlayfairDisplay',
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value; // attendu 0..1
  _GaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;

    // 1) Sanitize value (évite NaN/infini et <0 / >1)
    final v = (value.isFinite ? value : 0).clamp(0.0, 1.0);

    // 2) Piste sombre
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x26222222);
    canvas.drawCircle(center, radius, track);

    // 3) Angles
    const start = -math.pi / 2; // 12h
    final sweep = v * 2 * math.pi;

    // ⚠️ CanvasKit exige startAngle < endAngle pour le shader
    // Même si on va dessiner un arc de longueur 0, on crée le shader
    // avec un end légèrement supérieur.
    final shaderSweep = (sweep > 0 && sweep.isFinite) ? sweep : 1e-6;
    final shaderStart = start;
    final shaderEnd = start + shaderSweep;

    // 4) Pinceau gradient sweep "safe"
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: shaderStart,
        endAngle: shaderEnd, // garanti > startAngle
        colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    // 5) Dessin de l’arc (si v == 0, sweep == 0 → rien ne se voit, et c’est OK)
    final rectArc = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rectArc, start, sweep, false, arc);

    // 6) Gemme finale uniquement si progression visible
    if (v > 0) {
      final endAngle = start + sweep;
      final dx = center.dx + radius * math.cos(endAngle);
      final dy = center.dy + radius * math.sin(endAngle);
      final dot = Offset(dx, dy);

      final glow = Paint()
        ..color = const Color(0x80FFD700)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dot, 4.5, glow);

      final core = Paint()
        ..color = const Color(0xFFFFD700)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(dot, 2.2, core);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value;
}

// Ligne KPI premium (icône anneau + label + valeur)
// Ligne KPI premium (icône anneau + label + valeur) — anti-overflow
class _InfoKPI extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool compact;
  const _InfoKPI({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          // Icône anneau (légèrement réduite pour gagner ~6–8 px)
          Transform.scale(
            scale: compact ? 0.84 : 0.9,
            child: _LuxMiniIcon.gold(icon: icon),
          ),
          const SizedBox(width: 10),

          // Le label occupe l’espace central et s’ellipsise si trop long
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 12 : 13,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),

          const SizedBox(width: 8),

          // La valeur ne déborde jamais : se réduit si nécessaire
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13 : 14,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ====== Boutons hyper premium ======

class _LuxButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool danger; // rouge luxueux
  final bool outlined; // style contour verre fumé
  final bool compact; // petit bouton (dialog)
  final double radius;

  const _LuxButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.outlined = false,
    this.compact = false,
    this.radius = 20,
  });

  @override
  State<_LuxButton> createState() => _LuxButtonState();
}

class _LuxButtonState extends State<_LuxButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hPad = widget.compact ? 14.0 : 22.0;
    final vPad = widget.compact ? 10.0 : 12.0;

    final List<Color> grad = widget.danger
        ? const [Color(0xFFFF6B6B), Color(0xFFD24545)]
        : const [Color(0xFFFFD700), Color(0xFFA87C00)];
    final Color txt = widget.danger ? Colors.white : Colors.black;

    // Style OUTLINED verre fumé + contour dégradé animé
    final Widget outlined = AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: SweepGradient(
              startAngle: _c.value * 6.28318,
              endAngle: _c.value * 6.28318 + 6.28318,
              colors: [
                grad.first.withOpacity(.9),
                grad.last.withOpacity(.9),
                grad.first.withOpacity(.9)
              ],
              stops: const [0.0, .6, 1.0],
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(1.2),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius - 1.2),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.06), Colors.black12],
              ),
              border: Border.all(color: Colors.white10),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 3)),
              ],
            ),
            child: _content(
                color: widget.danger ? grad.first : AppColors.gold,
                textColor: Colors.white),
          ),
        );
      },
    );

    // Style FILL (pill gradient)
    final Widget filled = Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: grad),
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: [
          BoxShadow(
            color: (widget.danger ? Colors.redAccent : AppColors.gold)
                .withOpacity(.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _content(color: txt, textColor: txt),
    );

    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      scale: _down ? 0.98 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.radius),
        onHighlightChanged: (v) => setState(() => _down = v),
        onTap: widget.onTap,
        child: widget.outlined ? outlined : filled,
      ),
    );
  }

  Widget _content({required Color color, required Color textColor}) {
    final iconSize = widget.compact ? 16.0 : 18.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          // petit médaillon “verre fumé”
          Container(
            width: widget.compact ? 26 : 30,
            height: widget.compact ? 26 : 30,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(.14), Colors.black12],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white10),
            ),
            child: Icon(widget.icon, size: iconSize, color: textColor),
          ),
        ],
        Text(
          widget.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontFamily: 'PlayfairDisplay',
            fontSize: widget.compact ? 13 : 14,
            letterSpacing: .2,
          ),
        ),
      ],
    );
  }
}

// Raccourcis pratiques
// Bouton dangereux (dégradé rouge + halo + légère animation d’appui)
class _LuxDangerButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;
  const _LuxDangerButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_LuxDangerButton> createState() => _LuxDangerButtonState();
}

class _LuxDangerButtonState extends State<_LuxDangerButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final padH = widget.compact ? 16.0 : 22.0;
    final padV = widget.compact ? 10.0 : 12.0;
    final fs = widget.compact ? 13.0 : 15.0;

    return AnimatedScale(
      duration: const Duration(milliseconds: 90),
      scale: _down ? 0.985 : 1.0,
      child: InkWell(
        onHighlightChanged: (v) => setState(() => _down = v),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B6B), Color(0xFFD24545)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33FF6B6B),
                  blurRadius: 24,
                  offset: Offset(0, 10)),
              BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 14,
                  offset: Offset(0, 6)),
            ],
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // pastille verre fumé
              Container(
                width: widget.compact ? 28 : 32,
                height: widget.compact ? 28 : 32,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white.withOpacity(0.18), Colors.black12],
                  ),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.logout_rounded,
                    color: Colors.white, size: 18),
              ),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w800,
                  fontSize: fs,
                  letterSpacing: .2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bouton secondaire “ghost” (verre fumé) — parfait pour Annuler
class _LuxGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;
  const _LuxGhostButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final padH = compact ? 14.0 : 18.0;
    final padV = compact ? 8.0 : 10.0;
    final fs = compact ? 13.0 : 14.0;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withOpacity(0.08), Colors.black12],
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.w700,
            fontSize: fs,
          ),
        ),
      ),
    );
  }
}

// Section ancrée avec bordure luxe + contenu clair
class _LogoutSection extends StatelessWidget {
  const _LogoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _AnimatedLuxBorder(
      colors: const [Color(0xFFFFD700), Color(0xFFA87C00)],
      radius: 18,
      stroke: 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.lock_person_rounded, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                "Sécurité du compte",
                style: TextStyle(
                  color: AppColors.gold,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              "Vous pouvez vous déconnecter de cet appareil à tout moment.",
              style: TextStyle(
                  color: Colors.white60, fontFamily: 'PlayfairDisplay'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Spacer(),
                _LuxDangerButton(
                  label: "Se déconnecter",
                  onTap: () => performLogout(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldLine extends StatefulWidget {
  const _GoldLine({super.key});

  @override
  State<_GoldLine> createState() => _GoldLineState();
}

class _GoldLineState extends State<_GoldLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width * 0.45;
        final glowWidth = width * (0.3 + 0.2 * _controller.value);
        return Container(
          height: 2,
          width: width,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x22FFD700),
                Color(0x66FFD700),
                Color(0x22FFD700),
              ],
            ),
          ),
          child: Align(
            alignment: Alignment(
                -1.0 + 2.0 * _controller.value, Alignment.bottomCenter.y),
            child: Container(
              width: glowWidth * 0.1,
              height: 2,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFD700),
                    Color(0xFFA87C00),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66FFD700),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// --- HEADER + GREETING ULTRA PREMIUM ----------------------------------------
class PremiumHeader extends StatelessWidget {
  final String greeting;
  final String userName;
  final VoidCallback onProfile;
  const PremiumHeader({
    super.key,
    required this.greeting,
    required this.userName,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barre de titre + bouton profil verre fumé
        Row(
          children: [
            const _GoldTitle("Accueil"),
            const Spacer(),
            _GlassIconButton(
              icon: Icons.person_outline_rounded,
              onTap: onProfile,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _GreetingLine(text: "$greeting $userName 👋"),
      ],
    );
  }
}

/// Titre “Accueil” avec dégradé or + lueur discrète
class _GoldTitle extends StatelessWidget {
  final String text;
  const _GoldTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // glow doux
        Positioned.fill(
          top: 6,
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(boxShadow: [
                BoxShadow(
                    color: Color(0x22FFD700), blurRadius: 20, spreadRadius: 2)
              ]),
            ),
          ),
        ),
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(r),
          child: const Text(
            "Accueil",
            style: TextStyle(
              color: Colors.white, // requis par ShaderMask
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFamily: 'PlayfairDisplay',
              letterSpacing: .2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton profil “verre fumé” + halo
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
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
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: const Icon(Icons.person_outline_rounded, color: AppColors.gold),
      ),
    );
  }
}

/// Greeting centré gorgé d’or + underline animé
class _GreetingLine extends StatefulWidget {
  final String text;
  const _GreetingLine({required this.text});

  @override
  State<_GreetingLine> createState() => _GreetingLineState();
}

class _GreetingLineState extends State<_GreetingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: const TextStyle(
            color: Colors.white, // <- blanc
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: 'PlayfairDisplay',
            shadows: [
              Shadow(
                  color: Color(0x88000000),
                  blurRadius: 8,
                  offset: Offset(0, 2)),
            ],
          ),
        ),

        const SizedBox(height: 6),
        // trait doré animé (signature)
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final base = MediaQuery.sizeOf(context).width * 0.34;
            final w = base + base * .15 * _c.value;
            return Stack(
              children: [
                Container(
                  height: 2,
                  width: base * 1.25,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x22FFD700),
                        Color(0x66FFD700),
                        Color(0x22FFD700)
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 2,
                  width: w * .25,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Color(0x66FFD700),
                          blurRadius: 10,
                          spreadRadius: 2),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRAFFIC — Panel ULTRA PREMIUM (header + map + legend) — version autonome
// ─────────────────────────────────────────────────────────────────────────────
class TrafficPanelPremium extends StatelessWidget {
  final LatLng? center;
  final Set<Marker> markers;
  final VoidCallback? onTapVoir;
  final bool hasIncidents;
  final double height;

  const TrafficPanelPremium({
    Key? key,
    required this.center,
    this.markers = const {},
    this.onTapVoir,
    this.hasIncidents = false,
    this.height = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _glassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              _goldBadge(icon: Icons.traffic_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _GoldTitle("Trafic autour de vous"),
                    SizedBox(height: 2),
                    Text(
                      "Données en direct sur les axes proches",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _LiveChipLite(),
              const SizedBox(width: 10),
              _VoirButtonLite(onTap: onTapVoir),
            ],
          ),
          const SizedBox(height: 12),

          // Map
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  if (center != null)
                    GoogleMap(
                      initialCameraPosition:
                          CameraPosition(target: center!, zoom: 13.6),
                      compassEnabled: false,
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      trafficEnabled: true,
                      mapToolbarEnabled: false,
                      markers: markers,
                    )
                  else
                    const _MapPlaceholderLite(),

                  // vignette sombre + cadre
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(.10),
                              Colors.transparent,
                              Colors.black.withOpacity(.14),
                            ],
                            stops: const [0, .5, 1],
                          ),
                          border: Border.all(color: Colors.white10, width: 1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),

                  if (hasIncidents)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: _RibbonLite(label: "Incidents à proximité"),
                    ),
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: _GlassTagLite(
                        icon: Icons.traffic, label: "Trafic en direct"),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          // Légende
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendPillLite(color: Color(0xFF45E27A), label: "Fluide"),
              _LegendPillLite(color: Color(0xFFFFC44D), label: "Dense"),
              _LegendPillLite(color: Color(0xFFE55B5B), label: "Très dense"),
            ],
          ),
        ],
      ),
    );
  }
}

// —— petits éléments internes (versions “Lite”) ——
Widget _glassCard(
    {required double radius,
    required EdgeInsets padding,
    required Widget child}) {
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
            color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
      ],
    ),
    padding: padding,
    child: child,
  );
}

Widget _goldBadge({required IconData icon}) => Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.traffic_rounded, color: Colors.black),
    );

class _VoirButtonLite extends StatelessWidget {
  final VoidCallback? onTap;
  const _VoirButtonLite({this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33FFD700), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Text("Voir",
              style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2)),
          SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, size: 18, color: Colors.black),
        ]),
      ),
    );
  }
}

class _LiveChipLite extends StatefulWidget {
  const _LiveChipLite();
  @override
  State<_LiveChipLite> createState() => _LiveChipLiteState();
}

class _LiveChipLiteState extends State<_LiveChipLite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: .92, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: const Color(0xFF1A1A1A),
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
                    blurRadius: 10)
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text("LIVE",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class _LegendPillLite extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendPillLite({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFF101010),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(.35), blurRadius: 10)
                ])),
        const SizedBox(width: 6),
        const Text("", style: TextStyle(fontSize: 0)), // padding fix for layout
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _GlassTagLite extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GlassTagLite({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withOpacity(.55),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        const Icon(Icons.traffic, size: 16, color: AppColors.gold),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

class _RibbonLite extends StatelessWidget {
  final String label;
  const _RibbonLite({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
            colors: [Color(0xFFE05E5E), Color(0xFF9A1E1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59E05E5E), blurRadius: 14, offset: Offset(0, 6))
        ],
      ),
      child: Row(children: const [
        Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
        SizedBox(width: 6),
        Text("Incidents à proximité",
            style: TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _MapPlaceholderLite extends StatelessWidget {
  const _MapPlaceholderLite();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Text("Localisation en cours…",
          style: TextStyle(color: Colors.white54)),
    );
  }
}
