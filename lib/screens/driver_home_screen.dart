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
import 'package:intl/intl.dart';
import '../models/trip.dart';
import '../providers/driver_provider.dart';
import '../themes/app_theme.dart';
import 'package:ride_my_way/services/weather_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

String _formatEuroFr(double v) =>
    NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 2)
        .format(v); // ex: 604,01 €

// ─────────────────────────────────────────────────────────────────────────────
// Utilitaires
// ─────────────────────────────────────────────────────────────────────────────

Future<({double lat, double lng})?> getCoordinatesFromAddress(
    String address) async {
  const apiKey =
      'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI'; // 🔐 Remplace par ta vraie clé
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

// ─────────────────────────────────────────────────────────────────────────────
// Écran principal
// ─────────────────────────────────────────────────────────────────────────────

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // 🔔 suivi des courses proches (pour détecter les nouvelles)
  Set<String> _nearbyIds = {};
// 🎧 sonnerie en boucle
  final AudioPlayer _ringer = AudioPlayer();
  bool _isRinging = false;

  bool _isVisible = false;
  double _driverRating = 0.0;
  List<Map<String, dynamic>> _feedbacks = [];
  double _todayEarnings = 0.0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _todayEarningsSub;

  LatLng? _currentPosition;
  BitmapDescriptor? _customDriverIcon;

  late Timer _refreshTimer;
  List<DocumentSnapshot> _nearbyReservations = [];
  bool _hasNewNearbyCourse = false;

  // Avis (maquette premium)
  int? _starFilter; // null = Tous, sinon 5..1
  final Set<int> _expandedReviews = {}; // indices ouverts "Voir plus"
  String _greetingFor(DateTime dt) {
    final h = dt.hour;
    if (h >= 5 && h < 12) return "Bonjour";
    if (h >= 12 && h < 18) return "Bon après-midi";
    if (h >= 18 && h < 22) return "Bonsoir";
    return "Bonne nuit";
  }

  final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();
  static const AndroidNotificationChannel _nearbyChannel =
      AndroidNotificationChannel(
    'nearby_courses_channel',
    'Courses proches',
    description: 'Alertes de courses à proximité',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('urgent_alert'),
    enableVibration: true,
    showBadge: true,
  );

  DateTime? _lastNearbyAlertAt;
  final Duration _nearbyAlertCooldown = const Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    _loadVisibility();
    _startAutoRefresh();
    _loadDriverStats();
    _loadRecentFeedbacks();
    _loadCustomIcon();
    _getCurrentPosition();
    _listenTodayEarnings();
    _initLocalNotifications();
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _todayEarningsSub?.cancel();
    _stopRinger();
    _ringer.dispose();
    super.dispose();
  }

  Future<void> _startRinger() async {
    if (_isRinging) return;
    try {
      // ⚠️ place aussi le fichier dans android/app/src/main/res/raw/urgent_alert.mp3
      await _ringer.setAsset('assets/sounds/urgent_alert.mp3');
      await _ringer.setLoopMode(LoopMode.one);
      await _ringer.play();
      _isRinging = true;
    } catch (e) {
      debugPrint('Ringer start error: $e');
    }
  }

  Future<void> _stopRinger() async {
    if (!_isRinging) return;
    try {
      await _ringer.stop();
    } catch (_) {}
    _isRinging = false;
  }

  Future<void> _initLocalNotifications() async {
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _flnp.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (_) {
        if (mounted) showNearbyCoursesDialog(context);
      },
    );

    await _flnp
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_nearbyChannel);
  }

  Future<void> _showNearbyHeadsUp(
      {required String title, required String body}) async {
    await _flnp.show(
      1001,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _nearbyChannel.id,
          _nearbyChannel.name,
          channelDescription: _nearbyChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('urgent_alert'),
          enableVibration: true,
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
        ),
        iOS: const DarwinNotificationDetails(
            presentAlert: true, presentSound: true),
      ),
      payload: 'open_nearby_dialog',
    );
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _startOfNextDay(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));

  Future<void> _listenTodayEarnings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // bornes locales (minuit -> minuit+1)
    final now = DateTime.now();
    final start = _startOfDay(now);
    final end = _startOfNextDay(now);

    _todayEarningsSub?.cancel();

    _todayEarningsSub = FirebaseFirestore.instance
        .collection('reservations')
        .where('driverId', isEqualTo: uid)
        .where('status', isEqualTo: 'Terminée') // plus fiable
        .snapshots()
        .listen((snap) {
      double sum = 0.0;

      for (final d in snap.docs) {
        final data = d.data();

        // 1) choisir le bon champ date
        final ts = (data['completedAt'] ??
            data['timestamp'] ??
            data['createdAt']) as Timestamp?;
        if (ts == null) continue;

        final dt = ts
            .toDate(); // UTC → converti automatiquement en DateTime local pour les comparaisons
        if (dt.isBefore(start) || !dt.isBefore(end))
          continue; // garder uniquement "aujourd'hui"

        // 2) choisir le bon champ prix
        final price = (data['price'] ?? data['amount'] ?? data['fare']) as num?;
        sum += (price?.toDouble() ?? 0.0);
      }

      if (mounted) setState(() => _todayEarnings = sum);
    }, onError: (e) {
      debugPrint('❌ todayEarnings stream: $e');
    });
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
      final newDocs = await _fetchNearbyPendingReservations();

      // maj UI (liste + bouton qui clignote)
      final hasNew =
          newDocs.isNotEmpty && newDocs.length != _nearbyReservations.length;
      if (mounted) {
        setState(() {
          _hasNewNearbyCourse = hasNew;
          _nearbyReservations = newDocs;
        });
      }

      // set des IDs actuels
      final newIds = newDocs.map((d) => d.id).toSet();
      final newlyAdded = newIds.difference(_nearbyIds);

      // 1) si nouvelle(s) course(s) → heads-up + démarre sonnerie en boucle
      if (newlyAdded.isNotEmpty) {
        // anti-spam (tu as déjà _lastNearbyAlertAt / _nearbyAlertCooldown)
        final now = DateTime.now();
        final canAlert = _lastNearbyAlertAt == null ||
            now.difference(_lastNearbyAlertAt!) > _nearbyAlertCooldown;
        if (canAlert) {
          _lastNearbyAlertAt = now;
          final first = newDocs
              .firstWhere((d) => d.id == newlyAdded.first)
              .data() as Map<String, dynamic>;
          final from = (first['from'] ?? 'Départ').toString();
          final to = (first['to'] ?? 'Arrivée').toString();
          try {
            await _showNearbyHeadsUp(
              title: '🚗 Course proche disponible',
              body: '$from ➜ $to • touchez pour voir',
            );
          } catch (e) {
            debugPrint('Heads-up error: $e');
          }
        }
        await _startRinger(); // 🔊 boucle
      }

      // 2) s’il n’y a plus AUCUNE course proche → coupe la sonnerie
      if (newIds.isEmpty) {
        await _stopRinger();
      }

      // mémorise
      _nearbyIds = newIds;
    });
  }

  // ── Firestore fetchers ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRecentFeedbacks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      // ── 1) Base query
      Query<Map<String, dynamic>> baseQ = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('driverId', isEqualTo: uid)
          .where('fromDriver', isEqualTo: false);

      // ── 2) Tente avec orderBy (rapide si index dispo) ; sinon fallback sans index
      List<QueryDocumentSnapshot<Map<String, dynamic>>> fbDocs;
      try {
        fbDocs =
            (await baseQ.orderBy('timestamp', descending: true).limit(5).get())
                .docs;
      } on FirebaseException {
        final tmp = await baseQ.get();
        fbDocs = tmp.docs
          ..sort((a, b) => ((b.data()['timestamp'] as Timestamp?) ??
                  Timestamp(0, 0))
              .compareTo(
                  (a.data()['timestamp'] as Timestamp?) ?? Timestamp(0, 0)));
        if (fbDocs.length > 5) fbDocs = fbDocs.sublist(0, 5);
      }

      if (fbDocs.isEmpty) return [];

      // ── 3) Prépare IDs (<= 10 → ok pour whereIn)
      final passengerIds = <String>{};
      final reservationIds = <String>{};
      for (final d in fbDocs) {
        final data = d.data();
        final pid = data['passengerId'] as String?;
        final rid = data['reservationId'] as String?;
        if (pid != null && pid.isNotEmpty) passengerIds.add(pid);
        if (rid != null && rid.isNotEmpty) reservationIds.add(rid);
      }

      // Helper: fetch par lot sur __name__ (documentId)
      Future<Map<String, Map<String, dynamic>>> _fetchByIds(
        String collection,
        Set<String> ids,
      ) async {
        if (ids.isEmpty) return {};
        final snap = await FirebaseFirestore.instance
            .collection(collection)
            .where(FieldPath.documentId, whereIn: ids.toList())
            .get();
        return {for (final d in snap.docs) d.id: d.data()};
      }

      // ── 4) Chargement passagers + réservations (users → fallback passengers)
      Map<String, Map<String, dynamic>> usersById = {};
      try {
        usersById = await _fetchByIds('users', passengerIds);
        if (usersById.isEmpty) {
          usersById = await _fetchByIds('passengers', passengerIds);
        }
      } catch (_) {
        usersById = await _fetchByIds('passengers', passengerIds);
      }

      final reservationsById =
          await _fetchByIds('reservations', reservationIds);

      // ── 5) Construit la liste enrichie
      final result = <Map<String, dynamic>>[];
      for (final doc in fbDocs) {
        final fb = doc.data();
        final pid = fb['passengerId'] as String?;
        final rid = fb['reservationId'] as String?;

        final user = (pid != null) ? usersById[pid] : null;
        final res = (rid != null) ? reservationsById[rid] : null;

        // Nom passager: first/last → displayName → "Passager"
        final firstName =
            (user?['firstName'] ?? user?['prenom'] ?? '') as String;
        final lastName = (user?['lastName'] ?? user?['nom'] ?? '') as String;
        final displayName = (user?['displayName'] ?? '').toString();
        final combined = [firstName, lastName]
            .where((s) => s.trim().isNotEmpty)
            .join(' ')
            .trim();
        final passengerName = combined.isNotEmpty
            ? combined
            : (displayName.isNotEmpty ? displayName : 'Passager');

        // Trajet (compat origin/destination)
        final from = (res?['from'] ?? res?['origin'] ?? '') as String? ?? '';
        final to = (res?['to'] ?? res?['destination'] ?? '') as String? ?? '';

        result.add({
          ...fb,
          '_id': doc.id,
          'passengerName': passengerName,
          'from': from,
          'to': to,
        });
      }

      return result;
    } catch (e) {
      debugPrint("❌ fetchRecentFeedbacks (enrichi) : $e");
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
                          final isUrgent = duration.inMinutes <= 3;

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
    await _stopRinger();
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
    final greeting = _greetingFor(DateTime.now());

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
// ── Header responsive : 2 colonnes à parts égales, wrap en 2 lignes si étroit
            LayoutBuilder(
              builder: (context, c) {
                final isNarrow = c.maxWidth < 420; // breakpoint mobile étroit
                final double itemW =
                    isNarrow ? c.maxWidth : (c.maxWidth / 2) - 8;

                return Wrap(
                  spacing: 16, // espace horizontal entre colonnes
                  runSpacing: 14, // espace vertical si ça wrap
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    // ── Colonne gauche : salutation
                    SizedBox(
                      width: itemW,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            "${user?.firstName ?? 'Conducteur'} 👋",
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Colonne droite : capsule montant du jour
                    SizedBox(
                      width: itemW,
                      child: Align(
                        alignment: isNarrow
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.all(2.4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xFF9C7A23),
                                Color(0xFFFFE29F),
                                Color(0xFF9C7A23)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.gold.withOpacity(0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(38),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withOpacity(0.04),
                                          Colors.transparent
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E0E0E),
                                  borderRadius: BorderRadius.circular(38),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Votre gain du jour",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.gold,
                                        fontSize: 10, // petit descriptif doré
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .6,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    FittedBox(
                                      fit: BoxFit
                                          .scaleDown, // évite tout overflow
                                      child: Text(
                                        _formatEuroFr(_todayEarnings),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'PlayfairDisplay',
                                          fontSize: 28,
                                          fontWeight: FontWeight.w800,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
                              final isUrgent = diff.inMinutes <= 3;

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
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchRecentFeedbacks(),
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

                            // 🔹 Déclarations ici (avant tout widget)
                            final passengerName =
                                (fb['passengerName'] as String?) ?? 'Passager';
                            final fromAddr = (fb['from'] as String?)?.trim();
                            final toAddr = (fb['to'] as String?)?.trim();

                            final date =
                                (fb['timestamp'] as Timestamp?)?.toDate();
                            final rating =
                                (fb['rating'] as num?)?.toDouble() ?? 0.0;
                            final comment = (fb['comment'] as String?) ?? '';

                            // 🔹 Partie UI ensuite
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141414),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: AppColors.gold.withOpacity(0.15)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _nameAvatar(
                                          passengerName), // ✅ variable dynamique ici
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              passengerName, // ✅ plus de "const" ici
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (fromAddr != null &&
                                                toAddr != null)
                                              Text(
                                                "$fromAddr ➜ $toAddr",
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        date != null
                                            ? _formatFrenchDate(date)
                                            : "",
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _stars(rating),
                                  const SizedBox(height: 6),
                                  Text(
                                    comment,
                                    style: const TextStyle(
                                        color: Colors.white70, height: 1.4),
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
