import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  int _currentPage = 0;
  String _hintFrom = "Détection en cours...";
  List<Map<String, dynamic>> _trips = [];

  // Grille des rangs PAR NOMBRE DE TRAJETS
  static const int bronzeMin = 1; // >=1
  static const int argentMin = 100; // suggestion
  static const int orMin = 250; // ✅ Or à 250
  static const int diamantMin = 500; // ✅ Diamant à 500

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

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .get();

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

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return "${date.day}/${date.month} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
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

      setState(() {
        _fromController.text = city;
        _hintFrom = city;
      });
    } catch (_) {
      setState(() {
        _hintFrom = "Saisir votre point de départ";
      });
    }
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

          // ——— ICI: barre de progression + aide ———
          const SizedBox(height: 14),
          Text(nextLabel,
              style: const TextStyle(
                  color: Colors.white70, fontFamily: 'PlayfairDisplay')),
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
                  const SizedBox(height: 28),
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _fromController,
                    googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                    debounceTime: 800,
                    countries: ["fr"],
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
                  const SizedBox(height: 16),
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _toController,
                    googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                    debounceTime: 800,
                    countries: ["fr"],
                    fetchCoordinates: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                        "Entrer une destination", Icons.search),
                    onSuggestionClicked: (prediction) {
                      _toController.text = prediction.description!;
                      FocusScope.of(context).unfocus();
                    },
                    onEditingComplete: () {
                      final from = _fromController.text.trim();
                      final to = _toController.text.trim();
                      if (to.isNotEmpty)
                        context.go('/results?from=$from&to=$to');
                    },
                    overlayContainerBuilder: (child) => Material(
                      elevation: 2.0,
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      final from = _fromController.text.trim();
                      final to = _toController.text.trim();
                      if (from.isNotEmpty && to.isNotEmpty) {
                        context.go('/results?from=$from&to=$to');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Merci de renseigner le départ et la destination"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
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
                  const SizedBox(height: 24),
                  _homeButton(context, Icons.event_note, "Mes réservations",
                      '/reservations'),
                  _homeButton(context, Icons.favorite_border, "Mes favoris",
                      '/favorites'),
                  const SizedBox(height: 28),
                  FutureBuilder<_Reputation>(
                    future: _fetchPassengerReputation(),
                    builder: (context, snap) {
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
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _reputationFusion(rep),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  if (_trips.isEmpty)
                    const Center(
                        child: CircularProgressIndicator(color: AppColors.gold))
                  else
                    Column(
                      children: [
                        SizedBox(
                          height: 160,
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) =>
                                setState(() => _currentPage = index),
                            itemCount: _trips.length,
                            itemBuilder: (context, index) {
                              final trip = _trips[index];
                              return _TripCard(
                                title: trip['title'],
                                from: trip['from'],
                                to: trip['to'],
                                date: trip['date'],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _trips.length,
                            (index) => _buildDot(index == _currentPage),
                          ),
                        ),
                      ],
                    ),
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

  const _TripCard({
    required this.title,
    required this.from,
    required this.to,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final isRedirect = from.isEmpty && to.isEmpty;

    return FadeInUp(
      duration: const Duration(milliseconds: 400),
      child: Card(
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isRedirect
              ? Center(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/reservations'),
                    icon:
                        const Icon(Icons.directions_car, color: AppColors.gold),
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
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("$from ➔ $to",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    Text("Départ prévu : $date",
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13)),
                  ],
                ),
        ),
      ),
    );
  }
}
