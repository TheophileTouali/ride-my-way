// lib/screens/driver_home_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../providers/driver_provider.dart';
import '../themes/app_theme.dart';
import 'package:ride_my_way/services/weather_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Utilitaires
// ─────────────────────────────────────────────────────────────────────────────

Future<({double lat, double lng})?> getCoordinatesFromAddress(
    String address) async {
  const apiKey = 'REPLACE_ME_WITH_YOUR_API_KEY'; // 🔐 Remplace par ta vraie clé
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey',
  );

  try {
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'OK') {
        final result = data['results'][0];
        final location = result['geometry']['location'];
        return (
          lat: (location['lat'] as num).toDouble(),
          lng: (location['lng'] as num).toDouble()
        );
      } else {
        debugPrint("⚠️ Geocoding API status: ${data['status']}");
      }
    } else {
      debugPrint("❌ HTTP error: ${response.statusCode}");
    }
  } catch (e) {
    debugPrint("❌ Exception Geocoding: $e");
  }
  return null;
}

Future<WeatherInfo> getWeatherFromPosition() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception("La permission de localisation est requise.");
    }
  }
  final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);
  return await fetchWeather(position.latitude, position.longitude);
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèles simples / mocks
// ─────────────────────────────────────────────────────────────────────────────

class Testimonial {
  final String passengerName;
  final String avatarUrl;
  final double rating;
  final String comment;

  Testimonial({
    required this.passengerName,
    required this.avatarUrl,
    required this.rating,
    required this.comment,
  });
}

Future<Map<int, double>> fetchMonthlyRevenues() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception("Utilisateur non connecté");

  final snapshot = await FirebaseFirestore.instance
      .collection('reservations')
      .where('driverId', isEqualTo: uid)
      .where('status', isEqualTo: 'Terminée')
      .get();

  final Map<int, double> revenues = {};
  for (final doc in snapshot.docs) {
    final data = doc.data();
    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    final timestamp = data['timestamp'] as Timestamp?;
    if (timestamp == null) continue;

    final date = timestamp.toDate();
    final month = date.month; // 1..12
    revenues[month] = (revenues[month] ?? 0.0) + price;
  }
  return revenues;
}

Future<List<Testimonial>> fetchDriverTestimonials() async {
  await Future.delayed(const Duration(milliseconds: 600));
  return [
    Testimonial(
      passengerName: "Alice Dupont",
      avatarUrl: "https://randomuser.me/api/portraits/women/1.jpg",
      rating: 4.8,
      comment: "Très ponctuel et agréable !",
    ),
    Testimonial(
      passengerName: "Karim B.",
      avatarUrl: "https://randomuser.me/api/portraits/men/3.jpg",
      rating: 5.0,
      comment: "Un excellent trajet, merci 😊",
    ),
    Testimonial(
      passengerName: "Sophie L.",
      avatarUrl: "https://randomuser.me/api/portraits/women/6.jpg",
      rating: 4.5,
      comment: "Conduite fluide et conversation sympa.",
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran principal
// ─────────────────────────────────────────────────────────────────────────────

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isVisible = false;
  double _driverRating = 0.0;
  List<Map<String, dynamic>> _feedbacks = [];

  LatLng? _currentPosition;
  BitmapDescriptor? _customDriverIcon;

  late Timer _refreshTimer;
  List<DocumentSnapshot> _nearbyReservations = [];
  bool _hasNewNearbyCourse = false;

  // Avis (maquette premium)
  int? _starFilter; // null = Tous, sinon 5..1
  final Set<int> _expandedReviews = {}; // indices ouverts "Voir plus"

  @override
  void initState() {
    super.initState();
    _loadVisibility();
    _startAutoRefresh();
    _loadDriverStats();
    _loadRecentFeedbacks();
    _loadCustomIcon();
    _getCurrentPosition();
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  // ── Inits ────────────────────────────────────────────────────────────────

  Future<void> _loadCustomIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/car_gold.png',
    );
    if (!mounted) return;
    setState(() {
      _customDriverIcon = icon;
    });
  }

  Future<void> _getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
  }

  Future<void> _loadRecentFeedbacks() async {
    final feedbacks = await fetchRecentFeedbacks();
    if (!mounted) return;
    setState(() {
      _feedbacks = feedbacks;
    });
  }

  Future<void> _loadDriverStats() async {
    final stats = await fetchDriverStats();
    if (!mounted) return;
    setState(() {
      _driverRating = stats.note;
    });
  }

  Future<void> _loadVisibility() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
    if (!mounted) return;
    if (doc.exists && doc.data()!.containsKey('isVisible')) {
      setState(() {
        _isVisible = doc['isVisible'] as bool? ?? false;
      });
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final newData = await _fetchNearbyPendingReservations();

      if (newData.isNotEmpty && newData.length != _nearbyReservations.length) {
        setState(() {
          _hasNewNearbyCourse = true;
          _nearbyReservations = newData;
        });

        // Ping sonore court
        final urgentPlayer = AudioPlayer();
        try {
          await urgentPlayer.setAsset('assets/sounds/urgent_alert.mp3');
          await urgentPlayer.play();
        } catch (e) {
          debugPrint("Erreur lecture son d’urgence : $e");
        } finally {
          Future.delayed(const Duration(seconds: 2), urgentPlayer.dispose);
        }
      } else {
        setState(() {
          _hasNewNearbyCourse = false;
          _nearbyReservations = newData;
        });
      }
    });
  }

  // ── Firestore fetchers ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRecentFeedbacks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('feedbacks')
          .where('driverId', isEqualTo: uid)
          .get();

      final feedbacks = snapshot.docs
          .map((doc) => doc.data())
          .where((data) => data['fromDriver'] == false)
          .toList();

      // Tri par date décroissante
      feedbacks.sort((a, b) =>
          (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

      return feedbacks.take(5).toList();
    } catch (e) {
      debugPrint("❌ Erreur lors de la récupération des feedbacks : $e");
      return [];
    }
  }

  Widget _buildNearbyButton() {
    return ElevatedButton.icon(
      onPressed: () => showNearbyCoursesDialog(context),
      icon: const Icon(Icons.map, color: Colors.black),
      label: const Text("Voir les courses proches"),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  void showNearbyCoursesDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.grey.shade900,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Titre + fermer
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Courses proches...",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Contenu
                FutureBuilder<List<DocumentSnapshot>>(
                  future: _fetchNearbyPendingReservations(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child:
                              CircularProgressIndicator(color: AppColors.gold),
                        ),
                      );
                    }

                    final reservations = snapshot.data!;
                    if (reservations.isEmpty) {
                      return const Text(
                        "Aucune course disponible à proximité.",
                        style: TextStyle(color: Colors.white54),
                      );
                    }

                    return Expanded(
                      child: ListView.builder(
                        itemCount: reservations.length,
                        itemBuilder: (context, index) {
                          final doc = reservations[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final from = data['from'] ?? '';
                          final to = data['to'] ?? '';
                          final priceNum = (data['price'] as num?)?.toDouble();
                          final price = priceNum != null
                              ? priceNum.toStringAsFixed(2)
                              : 'N/A';
                          final date =
                              (data['timestamp'] as Timestamp).toDate();
                          final distanceNum =
                              (data['distance'] as num?)?.toDouble();
                          final distance = distanceNum != null
                              ? distanceNum.toStringAsFixed(1)
                              : '?';

                          final duration = date.difference(DateTime.now());
                          final isUrgent = duration.inMinutes <= 5;

                          return FadeInUp(
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade900,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on,
                                          color: AppColors.gold, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          "$from ➜ $to",
                                          style: const TextStyle(
                                            color: AppColors.gold,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      if (isUrgent)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            "URGENT",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Distance : $distance km",
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  Text("Prix : $price €",
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      try {
                                        await _acceptReservation(doc.id);
                                        if (mounted)
                                          Navigator.of(context).pop();
                                      } catch (e) {
                                        debugPrint(
                                            "❌ Erreur acceptReservation : $e");
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle_outline,
                                        color: Colors.black),
                                    label: Text(
                                      isUrgent
                                          ? "ACCEPTER IMMÉDIATEMENT"
                                          : "Accepter cette course",
                                      style:
                                          const TextStyle(color: Colors.black),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isUrgent
                                          ? Colors.redAccent
                                          : AppColors.gold,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      minimumSize: const Size.fromHeight(44),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<DocumentSnapshot>> _fetchNearbyPendingReservations() async {
    final List<DocumentSnapshot> nearby = [];

    try {
      final currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('status', isEqualTo: 'En attente')
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final fromLat = data['fromLat'] as num?;
        final fromLng = data['fromLng'] as num?;
        final from = data['from'] ?? 'Adresse inconnue';

        if (fromLat == null || fromLng == null) {
          debugPrint("⛔ Coordonnées manquantes pour $from → ignorée");
          continue;
        }

        final distanceKm = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              fromLat.toDouble(),
              fromLng.toDouble(),
            ) /
            1000.0;

        if (distanceKm <= 15.0) {
          nearby.add(doc);
        }
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la récupération des réservations : $e");
    }

    return nearby;
  }

  Future<void> _acceptReservation(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Utilisateur non connecté");

    final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
    final driverDoc = await driverRef.get();

    if (!driverDoc.exists) {
      throw Exception("Conducteur non trouvé dans Firestore");
    }

    final data = driverDoc.data();
    if (data == null) throw Exception("Aucune donnée pour ce conducteur");

    final firstName = data['firstName'] ?? 'Prénom';
    final lastName = data['lastName'] ?? 'Nom';
    final driverName = "$firstName $lastName";
    final vehicle = data['vehicle'] ?? 'Véhicule inconnu';

    final reservationRef =
        FirebaseFirestore.instance.collection('reservations').doc(docId);

    await reservationRef.update({
      'status': 'Confirmée',
      'driverId': uid,
      'driverName': driverName,
      'vehicle': vehicle,
    });

    debugPrint("✅ Course $docId acceptée par $driverName ($uid)");
  }

  Future<void> _toggleVisibility(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(uid)
        .update({'isVisible': value});
    if (!mounted) return;
    setState(() => _isVisible = value);
  }

  Future<List<Trip>> fetchDriverTrips() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('driverId', isEqualTo: uid)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Trip(
          id: doc.id,
          from: data['from'] ?? '',
          to: data['to'] ?? '',
          departureTime: (data['timestamp'] as Timestamp).toDate(),
          price: (data['price'] as num?)?.toDouble() ?? 0.0,
          status: data['status'] ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint("❌ ERREUR fetchDriverTrips: $e");
      return [];
    }
  }

  // ── Helpers Avis (maquette) ──────────────────────────────────────────────

  List<Map<String, dynamic>> _getFilteredFeedbacks() {
    if (_starFilter == null) return _feedbacks;
    return _feedbacks.where((fb) {
      final r = (fb['rating'] as num?)?.round() ?? 0;
      return r == _starFilter;
    }).toList();
  }

  Widget _reviewFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.gold : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _ratingDistribution(List<Map<String, dynamic>> feedbacks) {
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final fb in feedbacks) {
      final r = (fb['rating'] as num?)?.round() ?? 0;
      if (counts.containsKey(r)) counts[r] = counts[r]! + 1;
    }
    final total = feedbacks.isEmpty ? 1 : feedbacks.length;
    final order = [5, 4, 3, 2, 1];

    return Column(
      children: order.map((star) {
        final count = counts[star]!;
        final ratio = count / total;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: Text("$star",
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(
                  count.toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _nameAvatar(String name) {
    final parts = name.trim().split(RegExp(r"\s+"));
    String initials = parts.isEmpty
        ? "?"
        : (parts.length == 1
            ? parts.first[0]
            : "${parts.first[0]}${parts.last[0]}");
    initials = initials.toUpperCase();

    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.gold,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _formatFrenchDate(DateTime d) {
    const months = [
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
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }

  String _truncate(String text, int maxLen, {bool keepExpanded = false}) {
    if (keepExpanded || text.length <= maxLen) return text;
    return text.substring(0, maxLen).trimRight() + "…";
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.gold),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Quitter l’espace conducteur ?',
                    style: TextStyle(color: Colors.white)),
                content: const Text(
                    'Vous serez redirigé vers l’écran de connexion.',
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler',
                          style: TextStyle(color: Colors.white70))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Oui',
                          style: TextStyle(color: AppColors.gold))),
                ],
              ),
            );

            if (confirm != true) return;

            try {
              await FirebaseAuth.instance.signOut();
            } catch (_) {}
            if (context.mounted) context.go('/login-driver');
          },
        ),
        titleSpacing: 8,
        title: Row(
          children: [
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Espace conducteur',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isVisible ? "🟢 En ligne" : "🔴 Hors ligne",
              style: TextStyle(
                color: _isVisible ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
            Switch(
              value: _isVisible,
              onChanged: _toggleVisibility,
              activeColor: AppColors.gold,
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: AppColors.gold),
              tooltip: 'Déconnexion',
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('drivers')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .update({
                    'isLoggedIn': false,
                    'lastActive': Timestamp.now(),
                  });

                  await FirebaseAuth.instance.signOut();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.grey.shade900,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        content: const Row(
                          children: [
                            Icon(Icons.logout, color: AppColors.gold),
                            SizedBox(width: 12),
                            Text('Déconnexion réussie. À bientôt 👋',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    );

                    await Future.delayed(const Duration(milliseconds: 600));
                    context.go('/login-driver');
                  }
                } catch (e) {
                  debugPrint('Erreur déconnexion: $e');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade800,
                        content: const Text(
                            'Erreur lors de la déconnexion. Réessaie.',
                            style: TextStyle(color: Colors.white)),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Bienvenue",
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w400),
                    ),
                    Text(
                      "${user?.firstName ?? 'Conducteur'} 👋",
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        _driverRating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Météo
            const SizedBox(height: 32),
            _buildWeatherCard(),

            // Courses proches
            const SizedBox(height: 24),
            ...(_hasNewNearbyCourse
                ? [
                    Pulse(infinite: true, child: _buildNearbyButton()),
                  ]
                : _nearbyReservations.isEmpty
                    ? [
                        _buildNearbyButton(),
                      ]
                    : [
                        _infoCard(
                          title: "Courses proches à accepter 🛰️",
                          child: Column(
                            children: _nearbyReservations.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final from = data['from'] ?? '';
                              final to = data['to'] ?? '';
                              final priceNum =
                                  (data['price'] as num?)?.toDouble();
                              final price = priceNum != null
                                  ? priceNum.toStringAsFixed(2)
                                  : 'N/A';
                              final distance =
                                  (data['distance'] as num?)?.toDouble();
                              final distanceStr = distance != null
                                  ? distance.toStringAsFixed(1)
                                  : '?';
                              final date =
                                  (data['timestamp'] as Timestamp).toDate();

                              final now = DateTime.now();
                              final diff = date.difference(now);
                              final timeBefore = diff.inMinutes < 60
                                  ? "dans ${diff.inMinutes} min"
                                  : "dans ${diff.inHours} h";
                              final isUrgent = diff.inMinutes <= 5;

                              return FadeInUp(
                                duration: const Duration(milliseconds: 400),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF121212),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                        color: AppColors.gold.withOpacity(0.4),
                                        width: 1.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.gold.withOpacity(0.08),
                                        blurRadius: 10,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: const [
                                          Icon(Icons.route,
                                              color: AppColors.gold, size: 18),
                                          SizedBox(width: 6),
                                          Text("Trajet",
                                              style: TextStyle(
                                                  color: AppColors.gold,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text("$from ➜ $to",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const Icon(Icons.schedule,
                                              color: Colors.white54, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                              "Départ : ${date.toLocal().toString().split('.').first} ($timeBefore)",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.straighten,
                                              color: Colors.white54, size: 16),
                                          const SizedBox(width: 6),
                                          Text("Distance : $distanceStr km",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.attach_money,
                                              color: Colors.white54, size: 16),
                                          const SizedBox(width: 6),
                                          Text("Prix : $price €",
                                              style: const TextStyle(
                                                  color: Colors.white70)),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            try {
                                              await _acceptReservation(doc.id);
                                            } catch (e) {
                                              debugPrint(
                                                  "❌ Erreur acceptReservation : $e");
                                            }
                                          },
                                          icon: const Icon(Icons.check_circle,
                                              color: Colors.black),
                                          label: Text(
                                            isUrgent
                                                ? "ACCEPTER IMMÉDIATEMENT"
                                                : "Accepter cette course",
                                            style: const TextStyle(
                                                color: Colors.black),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isUrgent
                                                ? Colors.redAccent
                                                : AppColors.gold,
                                            foregroundColor: Colors.black,
                                            minimumSize:
                                                const Size.fromHeight(48),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30)),
                                            textStyle: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ]),

            const SizedBox(height: 24),

            // Trajets classés par statut
            DefaultTabController(
              length: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TabBar(
                    labelColor: AppColors.gold,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: AppColors.gold,
                    tabs: [
                      Tab(text: "À venir"),
                      Tab(text: "Effectués"),
                      Tab(text: "Annulés"),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.45,
                    child: FutureBuilder<List<Trip>>(
                      future: fetchDriverTrips(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.gold));
                        }

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return const Center(
                            child: Text("Aucun trajet trouvé.",
                                style: TextStyle(color: Colors.white54)),
                          );
                        }

                        final trips = snapshot.data!;
                        final now = DateTime.now();

                        final Map<String, List<Trip>> categorizedTrips = {
                          'À venir': trips
                              .where((t) =>
                                  t.status == 'Confirmée' &&
                                  t.departureTime.isAfter(now))
                              .toList(),
                          'Effectués': trips
                              .where((t) => t.status == 'Terminée')
                              .toList(),
                          'Annulés': trips
                              .where((t) => t.status == 'Annulée')
                              .toList(),
                        };

                        return TabBarView(
                          children: categorizedTrips.entries.map((entry) {
                            final status = entry.key;
                            final filtered = entry.value;

                            if (filtered.isEmpty) {
                              return Center(
                                child: Text("Aucun trajet $status.",
                                    style:
                                        const TextStyle(color: Colors.white54)),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) =>
                                  _tripCard(context, filtered[i]),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildStatsSection(),
            const SizedBox(height: 24),
            _buildRevenueChart(),

            const SizedBox(height: 24),

            // Avis passagers
            FutureBuilder<List<Testimonial>>(
              future: fetchDriverTestimonials(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.gold));
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _infoCard(
                      title: "Avis récents — Ce que disent vos passagers",
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filtres
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _reviewFilterChip(
                                  label: "Tous",
                                  selected: _starFilter == null,
                                  onTap: () =>
                                      setState(() => _starFilter = null)),
                              _reviewFilterChip(
                                  label: "5 étoiles",
                                  selected: _starFilter == 5,
                                  onTap: () => setState(() => _starFilter = 5)),
                              _reviewFilterChip(
                                  label: "4 étoiles",
                                  selected: _starFilter == 4,
                                  onTap: () => setState(() => _starFilter = 4)),
                              _reviewFilterChip(
                                  label: "3 étoiles",
                                  selected: _starFilter == 3,
                                  onTap: () => setState(() => _starFilter = 3)),
                              _reviewFilterChip(
                                  label: "2 étoiles",
                                  selected: _starFilter == 2,
                                  onTap: () => setState(() => _starFilter = 2)),
                              _reviewFilterChip(
                                  label: "1 étoile",
                                  selected: _starFilter == 1,
                                  onTap: () => setState(() => _starFilter = 1)),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Répartition
                          _ratingDistribution(_feedbacks),
                          const SizedBox(height: 12),

                          // Liste des avis
                          ..._getFilteredFeedbacks()
                              .asMap()
                              .entries
                              .map((entry) {
                            final i = entry.key;
                            final fb = entry.value;
                            final rating =
                                (fb['rating'] as num?)?.toDouble() ?? 0.0;
                            final date =
                                (fb['timestamp'] as Timestamp?)?.toDate();
                            final commentRaw =
                                (fb['comment'] as String?)?.trim() ?? "—";

                            final isExpanded = _expandedReviews.contains(i);
                            final comment = _truncate(commentRaw, 170,
                                keepExpanded: isExpanded);

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: AppColors.gold.withOpacity(0.15)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 6)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _nameAvatar("Passager"),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          "Passager",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                          date != null
                                              ? _formatFrenchDate(date)
                                              : "",
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(rating.toStringAsFixed(1),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16)),
                                      const SizedBox(width: 6),
                                      _stars(rating),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(comment,
                                      style: const TextStyle(
                                          color: Colors.white70, height: 1.4)),
                                  if (commentRaw.length > 170)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () {
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedReviews.remove(i);
                                            } else {
                                              _expandedReviews.add(i);
                                            }
                                          });
                                        },
                                        child: Text(
                                          isExpanded
                                              ? "Voir moins"
                                              : "Voir plus",
                                          style: const TextStyle(
                                              color: AppColors.gold,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Voir profil
            ElevatedButton.icon(
              onPressed: () => context.go('/driver-profile'),
              icon: const Icon(Icons.person, color: AppColors.black),
              label: const Text("Voir mon profil"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.black,
                minimumSize: const Size.fromHeight(56),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Widgets secondaires ──────────────────────────────────────────────────

  Widget _testimonialCard(Testimonial t) {
    return FadeInUp(
      duration: const Duration(milliseconds: 400),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade800),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
                radius: 24, backgroundImage: NetworkImage(t.avatarUrl)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.passengerName,
                      style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                          i < t.rating.floor()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 16,
                          color: Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t.comment,
                      style: const TextStyle(
                          color: Colors.white70, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return FutureBuilder<WeatherInfo>(
      future: _fetchWeatherFromCurrentLocation(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _loadingCard("Chargement météo...");
        }

        final weather = snapshot.data!;
        return _infoCard(
          title: "Météo à ${weather.city}",
          child: Row(
            children: [
              // Bloc gauche
              Container(
                width: 100,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Image.network(weather.iconUrl, width: 36),
                    const SizedBox(height: 8),
                    Text(weather.city,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13)),
                    Text(
                      "${weather.temperature.toStringAsFixed(1)}°C",
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Bloc droit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _weatherDetailRow("🌥️", weather.condition),
                    const SizedBox(height: 6),
                    _weatherDetailRow("💨", "${weather.windSpeed} km/h"),
                    const SizedBox(height: 6),
                    _weatherDetailRow("💧", "${weather.humidity} %"),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<WeatherInfo> _fetchWeatherFromCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Les services de localisation sont désactivés.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permission de localisation refusée.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permissions de localisation refusées définitivement.');
    }

    final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    return await fetchWeather(position.latitude, position.longitude);
  }

  Widget _weatherDetailRow(String icon, String value) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return FutureBuilder<DriverStats>(
      future: fetchDriverStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _loadingCard("Chargement stats...");
        final stats = snapshot.data!;
        return _infoCard(
          title: "Mes statistiques",
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statColumn(
                  Icons.directions_car, "${stats.nbTrajets}", "Trajets"),
              _statColumn(
                  Icons.map_rounded, "${stats.totalKm} km", "Kilomètres"),
              _statColumn(
                  Icons.star_rounded, stats.note.toStringAsFixed(1), "Note"),
            ],
          ),
        );
      },
    );
  }

  Widget _stars(double rating) {
    final full = rating.floor();
    final hasHalf = (rating - full) >= 0.5;
    const total = 5;

    final icons = <Widget>[];
    for (int i = 0; i < total; i++) {
      if (i < full) {
        icons
            .add(const Icon(Icons.star_rounded, size: 14, color: Colors.amber));
      } else if (i == full && hasHalf) {
        icons.add(
            const Icon(Icons.star_half_rounded, size: 14, color: Colors.amber));
      } else {
        icons.add(const Icon(Icons.star_border_rounded,
            size: 14, color: Colors.amber));
      }
    }
    return Row(children: icons);
  }

  Widget _statColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.gold, size: 30),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.white54)),
      ],
    );
  }

  Widget _buildRevenueChart() {
    final months = [
      'Jan',
      'Fév',
      'Mar',
      'Avr',
      'Mai',
      'Juin',
      'Juil',
      'Août',
      'Sept',
      'Oct',
      'Nov',
      'Déc'
    ];

    return FutureBuilder<Map<int, double>>(
      future: fetchMonthlyRevenues(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _loadingCard("Chargement revenus...");

        final revenues = snapshot.data!;
        // background bar max Y (must be a double)
        final double bgMaxY = (() {
          if (revenues.values.isEmpty) return 800.0;
          final double maxRevenue =
              revenues.values.reduce((a, b) => a > b ? a : b);
          // 20% headroom, clamp to sensible bounds, then force to double
          return (maxRevenue * 1.2).clamp(200.0, 5000.0).toDouble();
        })();

        return _infoCard(
          title: "Mes revenus (mois) 💸",
          child: SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipMargin: 8,
                    getTooltipItem: (group, _, rod, __) {
                      final idx = group.x.toInt().clamp(0, 11);
                      return BarTooltipItem(
                        "${months[idx]} : ${rod.toY.toInt()}€",
                        const TextStyle(
                            color: AppColors.gold, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, _) => Text(
                        "${value.toInt()}€",
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt().clamp(0, 11);
                        return Text(
                          months[i],
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        );
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barGroups: List.generate(12, (index) {
                  final revenue = revenues[index + 1] ?? 0.0;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: revenue,
                        width: 18,
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(6),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: bgMaxY, // ← use the computed double
                          color: Colors.white12,
                        ),
                      ),
                    ],
                  );
                }),
              ),
              swapAnimationDuration: const Duration(milliseconds: 600),
              swapAnimationCurve: Curves.easeOutExpo,
            ),
          ),
        );
      },
    );
  }

  Widget _infoCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.gold, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _loadingCard(String title) {
    return _infoCard(
      title: title,
      child:
          const Center(child: CircularProgressIndicator(color: AppColors.gold)),
    );
  }

  // ── Petits helpers de formatage ──────────────────────────────────────────

  Widget _tripCard(BuildContext context, Trip trip) {
    final isSmall = MediaQuery.of(context).size.width < 380;

    return GestureDetector(
      onTap: () => context.go('/driver/trip/${trip.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.location_on, color: Color(0xFFFFD700), size: 18),
                    SizedBox(width: 6),
                    Text(
                      "Trajet",
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .6),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: Colors.white60, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      trip.departureTime
                          .toLocal()
                          .toIso8601String()
                          .split('T')
                          .first,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.euro, color: Colors.white60, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      trip.price.toStringAsFixed(2),
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 2),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: isSmall ? 15 : 16,
                          color: Colors.white,
                          height: 1.35),
                      children: [
                        TextSpan(
                            text: trip.from,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFD700))),
                        const TextSpan(
                            text: "  ➜  ",
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w500)),
                        TextSpan(
                            text: trip.to,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFD700))),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return "$y-$m-$d $hh:$mm";
  }

  String _timeUntil(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return "trajet passé";
    if (diff.inDays >= 1) {
      final d = diff.inDays;
      return "dans $d jour${d > 1 ? 's' : ''}";
    }
    if (diff.inHours >= 1) {
      return "dans ${diff.inHours} h";
    }
    return "dans ${diff.inMinutes} min";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats conducteur
// ─────────────────────────────────────────────────────────────────────────────

class DriverStats {
  final int nbTrajets;
  final int totalKm;
  final double note;

  DriverStats(
      {required this.nbTrajets, required this.totalKm, required this.note});
}

Future<DriverStats> fetchDriverStats() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception("Utilisateur non connecté");

  final reservationsSnapshot = await FirebaseFirestore.instance
      .collection('reservations')
      .where('driverId', isEqualTo: uid)
      .where('status', whereIn: ['Confirmée', 'Terminée']).get();

  final trajets = reservationsSnapshot.docs;
  int totalKm = 0;

  for (final doc in trajets) {
    final data = doc.data();
    totalKm += (data['distance'] as num?)?.round() ?? 0;
  }

  final feedbacksSnapshot = await FirebaseFirestore.instance
      .collection('feedbacks')
      .where('driverId', isEqualTo: uid)
      .where('fromDriver', isEqualTo: false)
      .get();

  double totalRating = 0.0;
  int nbRatings = 0;

  for (final doc in feedbacksSnapshot.docs) {
    final data = doc.data();
    final rating = (data['rating'] as num?)?.toDouble();
    if (rating != null) {
      totalRating += rating;
      nbRatings++;
    }
  }

  return DriverStats(
    nbTrajets: trajets.length,
    totalKm: totalKm,
    note: nbRatings > 0 ? (totalRating / nbRatings) : 0.0,
  );
}
