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

import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

// ---- Config clé Google (évite le hardcode; fallback si non fournie) ----
const String kGooglePlacesApiKey = String.fromEnvironment(
  'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI',
  defaultValue: 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI',
);

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

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  String _hintFrom = "Détection en cours...";
  List<Map<String, dynamic>> _trips = [];
  Map<String, dynamic>? _weather;
  bool _weatherLoading = false;

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

    // A) Avis chauffeurs : unicité par driverId (dernier avis gardé)
    final fbSnap = await FirebaseFirestore.instance
        .collection('feedbacks')
        .where('passengerId', isEqualTo: uid)
        .where('fromDriver', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .get();

    final allReviews =
        fbSnap.docs.map((d) => Map<String, dynamic>.from(d.data())).toList();

    final Map<String, Map<String, dynamic>> latestByDriver = {};
    for (final review in allReviews) {
      final driverId = (review['driverId'] ?? 'unknown').toString();
      latestByDriver.putIfAbsent(driverId, () => review);
    }
    final reviews = latestByDriver.values.toList();

    final total = reviews.length;
    final sum = reviews.fold<double>(
        0.0, (s, r) => s + ((r['rating'] ?? 0) as num).toDouble());
    final double avg = total == 0 ? 0.0 : (sum / total).toDouble();
    final satisfied =
        reviews.where((r) => ((r['rating'] ?? 0) as num) >= 4).length;

    // B) Réservations : respect%, trajets, dernier chauffeur, dépenses
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
      if (by.contains('passager') ||
          by.contains('passenger') ||
          by.contains('user') ||
          by.contains('client')) {
        return true;
      }
      return false;
    }

    DateTime? _extractDate(Map<String, dynamic> m) {
      for (final key in ['timestamp', 'endTime', 'startTime', 'createdAt']) {
        final v = m[key];
        if (v is Timestamp) return v.toDate();
      }
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

    final denom = completed + canceledByPassenger;
    final double respectPct = denom == 0 ? 100.0 : (completed / denom) * 100.0;

    final String? lastDriverId =
        lastResData != null ? (lastResData!['driverId'] as String?) : null;
    final String? lastDriverName =
        lastResData != null ? (lastResData!['driverName'] as String?) : null;

    // C) Progression vers le prochain rang (basé trajets)
    final double progressToNext = _progressToNextByTrips(completed);

    return _Reputation(
      avg: avg,
      satisfied: satisfied,
      total: total,
      reviews: reviews,
      respectPct: respectPct,
      lastDriverId: lastDriverId,
      lastDriverName: lastDriverName,
      completedTrips: completed,
      totalSpend: totalSpend,
      progressToNext: progressToNext,
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
    if (_weatherLoading) {
      return const _Shimmer(height: 74);
    }
    if (_weather == null) return const SizedBox.shrink();

    final t = (_weather!['t'] as double).toStringAsFixed(1);
    final feels = (_weather!['feels'] as double).toStringAsFixed(1);
    final wind = (_weather!['wind'] as double).toStringAsFixed(0);
    final code = _weather!['code'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(_wmoIcon(code), color: AppColors.gold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _wmoLabel(code),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Ressenti $feels° • Vent $wind km/h",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            "$t°",
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
        ],
      ),
    );
  }

  Widget _reputationCard(_Reputation rep) {
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        _repRow("Note globale", "⭐ ${rep.avg.toStringAsFixed(1)} / 5"),
        _repRow("Distinction", _medalFrom(rep.avg)),
        _repRow("Respect des trajets",
            "${rep.respectPct.isNaN ? 0 : rep.respectPct.round()} %"),
        _repRow("Chauffeurs satisfaits", "${rep.satisfied} / ${rep.total}"),
      ]),
    );
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

  // ── FUSION : Réputation + Avis + Progression ──
  Widget _reputationFusion(_Reputation rep) {
    final rank = _rankFromTrips(rep.completedTrips);

    // Libellé + objectif (avec les nouveaux paliers : Or=250, Diamant=500)
    String nextLabel;
    int nextTarget;
    if (rank == "Voyageur Diamant") {
      nextLabel = "Rang maximum atteint";
      nextTarget = diamantMin; // 500
    } else if (rank == "Voyageur d'Or") {
      nextLabel = "Progrès vers Voyageur Diamant ($diamantMin)";
      nextTarget = diamantMin; // 500
    } else if (rank == "Voyageur d'Argent") {
      nextLabel = "Progrès vers Voyageur d'Or ($orMin)";
      nextTarget = orMin; // 250
    } else if (rank == "Voyageur de Bronze") {
      nextLabel = "Progrès vers Voyageur d'Argent ($argentMin)";
      nextTarget = argentMin; // ton palier Argent
    } else {
      nextLabel = "Progrès vers Voyageur de Bronze ($bronzeMin)";
      nextTarget = bronzeMin; // 1
    }

    final tooltipText = rank == "Voyageur Diamant"
        ? "Félicitations ! Vous avez atteint le rang maximum."
        : "Il vous reste ${nextTarget - rep.completedTrips} trajets pour atteindre le prochain rang.";

    final currency =
        NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 0);

    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.gold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Voyageur d'excellence",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.gold, size: 18),
                  const SizedBox(width: 6),
                  Text("${rep.avg.toStringAsFixed(1)} / 5",
                      style: const TextStyle(
                          color: AppColors.gold, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Infos
          _fusionInfoRow("Distinction", rank),
          _fusionInfoRow("Trajets effectués", "${rep.completedTrips}"),
          _fusionInfoRow("Respect des trajets",
              "${rep.respectPct.isNaN ? 0 : rep.respectPct.round()} %"),
          _fusionInfoRow(
              "Chauffeurs satisfaits", "${rep.satisfied} / ${rep.total}"),
          _fusionInfoRow("Cumul dépensé", currency.format(rep.totalSpend)),

          const SizedBox(height: 14),
          Tooltip(
            message: tooltipText,
            preferBelow: true,
            child: Text(
              rank == "Voyageur Diamant"
                  ? "Rang maximum atteint"
                  : (rank == "Voyageur d'Or"
                      ? "Progrès vers Voyageur Diamant ($diamantMin)"
                      : (rank == "Voyageur d'Argent"
                          ? "Progrès vers Voyageur d'Or ($orMin)"
                          : (rank == "Voyageur de Bronze"
                              ? "Progrès vers Voyageur d'Argent ($argentMin)"
                              : "Progrès vers Voyageur de Bronze ($bronzeMin)"))),
              style: const TextStyle(
                  color: Colors.white70, fontFamily: 'PlayfairDisplay'),
            ),
          ),
          const SizedBox(height: 8),
          _progressBar(rep.progressToNext),
          if (rank != "Voyageur Diamant") ...[
            const SizedBox(height: 6),
            Text(
              "${rep.completedTrips} / $nextTarget "
              "(${(rep.progressToNext * 100).clamp(0, 100).toStringAsFixed(0)} %)",
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],

          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white10),
          const SizedBox(height: 14),

          Row(
            children: const [
              Icon(Icons.rate_review_outlined, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                "Avis des chauffeurs",
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (rep.reviews.isEmpty)
            const Text("Aucun avis de chauffeur pour le moment.",
                style: TextStyle(color: Colors.white38))
          else
            SizedBox(
              height: 160,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.9),
                itemCount: rep.reviews.length,
                itemBuilder: (context, index) {
                  final r = rep.reviews[index];
                  final rating = ((r['rating'] ?? 0) as num).toDouble();
                  final comment = (r['comment'] ?? '') as String;
                  final ts = r['timestamp'] as Timestamp?;
                  final dateStr = ts != null ? _frShortDate(ts.toDate()) : "";
                  return _reviewCard(
                    stars: _starRow(rating),
                    comment: comment,
                    footer: dateStr.isEmpty ? "" : "• $dateStr",
                  );
                },
              ),
            ),
        ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Accueil",
                          style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'PlayfairDisplay')),
                      IconButton(
                        icon: const Icon(Icons.person_outline,
                            color: AppColors.gold),
                        onPressed: () => context.go('/profile'),
                        tooltip: 'Profil',
                      ),
                    ],
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
                          child: Text(
                            "$greeting $userName 👋",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'PlayfairDisplay',
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _weatherSection(),
                        const SizedBox(height: 6),
                        const Text(
                          "Préparez-vous à vivre un trajet d’exception. ✨",
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              fontFamily: 'PlayfairDisplay'),
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
                          const Icon(Icons.location_off,
                              color: Colors.redAccent),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              "Activez la localisation pour détecter votre ville automatiquement.",
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          TextButton(
                            onPressed: _openLocationSettings,
                            child: const Text("Activer",
                                style: TextStyle(color: Colors.redAccent)),
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
                        "Entrer une destination", Icons.search),
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
                        child: const Center(
                          child: Text(
                            "Trouver un véhicule",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              fontFamily: 'PlayfairDisplay',
                            ),
                          ),
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
                          height: 200,
                          child: PageView.builder(
                            controller: _pageController,
                            padEnds: false,
                            physics: const BouncingScrollPhysics(),
                            // ❌ on retire ce setState global :
                            // onPageChanged: (index) => setState(() => _currentPage = index),
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
                                color: AppColors.gold,
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

                  const SizedBox(height: 28),
                  const SizedBox(height: 28),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Provider.of<UserProvider>(context, listen: false)
                            .logout();
                        context.go('/login');
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text("Se déconnecter"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
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
      prefixIcon: Icon(icon, color: AppColors.gold),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.gold),
      ),
    );
  }

  Widget _homeButton(
      BuildContext context, IconData icon, String label, String route) {
    return InkWell(
      onTap: () => context.go(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'PlayfairDisplay')),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    final isRedirect = from.isEmpty && to.isEmpty;
    final isLastTrip = title == 'Dernier trajet';

    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isRedirect
            ? Center(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/reservations'),
                  icon: const Icon(Icons.directions_car, color: AppColors.gold),
                  label: const Text(
                    "Voir tous mes trajets",
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    foregroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Infos trajet
                  Text(
                    "$from ➔ $to",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "Départ prévu : $date",
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),

                  // Bouton en bas à droite UNIQUEMENT pour le dernier trajet
                  if (isLastTrip && onRebook != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: TextButton.icon(
                        onPressed: onRebook,
                        icon: const Icon(Icons.refresh,
                            color: AppColors.gold, size: 18),
                        label: const Text(
                          "Refaire ce trajet",
                          style: TextStyle(
                            color: AppColors.gold,
                            fontFamily: 'PlayfairDisplay',
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
