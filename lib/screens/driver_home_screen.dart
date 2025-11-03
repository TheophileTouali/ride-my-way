// lib/screens/driver_home_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';

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
// Lux UI – helpers visuels premium (sans impact logique)
// ─────────────────────────────────────────────────────────────────────────────
class Lux {
  static const gold1 = Color(0xFFFFD700);
  static const gold2 = Color(0xFFA87C00);

  static TextStyle title([double fs = 18]) => TextStyle(
        fontFamily: 'PlayfairDisplay',
        fontWeight: FontWeight.w800,
        fontSize: fs,
        letterSpacing: .2,
        color: Colors.white,
        shadows: const [
          Shadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      );

  static TextStyle goldLabel([double fs = 12]) => TextStyle(
        color: Lux.gold1,
        fontWeight: FontWeight.w700,
        fontSize: fs,
        letterSpacing: .5,
      );

  static BoxDecoration glass({double r = 16, Color? stroke}) => BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(.06), Colors.black12],
        ),
        // léger contour pour la lecture
        border: Border.all(color: stroke ?? Colors.white12),
      );

  static Widget goldGradientText(String text, {double fs = 22}) {
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Lux.gold1, Lux.gold2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r),
      child: Text(text, style: Lux.title(fs).copyWith(color: Colors.white)),
    );
  }

  static Widget heroEarningCapsule(String amount, {bool center = false}) {
    return Container(
      padding: const EdgeInsets.all(2.2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9C7A23), Color(0xFFFFE29F), Color(0xFF9C7A23)],
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Lux.gold1.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E0E),
          borderRadius: BorderRadius.circular(38),
        ),
        child: Column(
          crossAxisAlignment:
              center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text("Votre gain du jour", style: Lux.goldLabel(10)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(amount, style: Lux.title(28)),
            ),
          ],
        ),
      ),
    );
  }

  static Widget goldSwitchChip({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: Lux.glass(r: 999),
      child: Row(
        children: [
          Text(value ? "🟢 En ligne" : "🔴 Hors ligne",
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(width: 6),
          Transform.scale(
            scale: .9,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.black,
              activeTrackColor: Lux.gold1,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ],
      ),
    );
  }

  static Widget glassCard({
    required String title,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    double radius = 16,
  }) {
    return Container(
      padding: padding,
      decoration: Lux.glass(r: radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Lux.goldLabel(13)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  static Widget countdownChip(Duration d, {bool urgent = false}) {
    final str =
        d.inMinutes < 60 ? "dans ${d.inMinutes} min" : "dans ${d.inHours} h";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: urgent ? Colors.redAccent : Colors.white10,
        border: Border.all(
          color: urgent ? Colors.redAccent : Colors.white24,
        ),
      ),
      child: Text(
        str.toUpperCase(),
        style: TextStyle(
          color: urgent ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: .6,
        ),
      ),
    );
  }

  // Dégradé de fond noir premium
  static const _darkGrad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C0C0C), Color(0xFF141414)],
  );

  /// Carte verre fumé + bordure dégradée or + halo interne
  static Widget goldGlass({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    double radius = 20,
  }) {
    return Stack(
      children: [
        // halo externe doux
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius + 4),
            boxShadow: [
              BoxShadow(
                color: Lux.gold1.withOpacity(.10),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
        ),
        // bordure dégradée or
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius + 2),
            gradient: const LinearGradient(
              colors: [Color(0x33FFD700), Color(0x338A6A0A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // fond verre (très sombre) + stroke intérieur
        Container(
          margin: const EdgeInsets.all(1.2),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: _darkGrad,
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: child,
        ),
      ],
    );
  }

  /// Bouton premium noir & or avec micro-hover/press
  static Widget premiumButton({
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    bool danger = false,
    EdgeInsets padding =
        const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
  }) {
    final bg = danger ? Colors.redAccent : Lux.gold1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: LinearGradient(
          colors: danger
              ? [Colors.redAccent.shade400, Colors.redAccent.shade200]
              : [const Color(0xFFE7C65C), Lux.gold2],
        ),
        boxShadow: [
          BoxShadow(
            color: bg.withOpacity(.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onPressed,
          splashColor: Colors.black12,
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.black, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ligne méteo “icône + texte” avec typographie lux
  static Widget metric(String emoji, String text) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

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

  Widget _buildReviewTile({
    required String name,
    required double rating,
    required String comment,
    DateTime? date,
    String? from,
    String? to,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 450), // ✅ au lieu de 450.ms
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (_, v, __) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - v)),
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF111111), Color(0xFF0A0A0A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: AppColors.gold.withOpacity(.20)),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _nameAvatar(name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            if (from != null && to != null)
                              Text(
                                "$from ➜ $to",
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Text(
                        date != null ? _formatFrenchDate(date) : "",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _stars(rating),
                  const SizedBox(height: 8),
                  Text(
                    comment,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.32,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────
// Badges & legend — ultra premium
// ──────────────────────────────────────────────────────────────

  Widget _goldBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [Color(0xFFEED27A), Color(0xFFA87C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Lux.gold1.withOpacity(.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _statusLegendDot({
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
// Trajets classés par statut — ULTRA PREMIUM (dans _DriverHomeScreenState)
// ────────────────────────────────────────────────────────────────────────────
  Widget _buildTripsSection() {
    return FutureBuilder<List<Trip>>(
      future: fetchDriverTrips(), // ← méthode existante de ta classe
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: CircularProgressIndicator(color: AppColors.gold),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _infoCard(
            // ← méthode existante (garde ta version)
            title: "Trajets",
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text("Aucun trajet trouvé.",
                    style: TextStyle(color: Colors.white54)),
              ),
            ),
          );
        }

        final trips = snapshot.data!;
        final now = DateTime.now();

        final upcoming = trips
            .where(
                (t) => t.status == 'Confirmée' && t.departureTime.isAfter(now))
            .toList();
        final done = trips.where((t) => t.status == 'Terminée').toList();
        final canceled = trips.where((t) => t.status == 'Annulée').toList();

        final pages = {
          'À venir': upcoming,
          'Effectués': done,
          'Annulés': canceled,
        };

        return Lux.goldGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header lux ──────────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: Lux.goldGradientText("Trajets classés par statut",
                          fs: 18)),
                  const SizedBox(width: 12),
                  _goldBadge("${trips.length} trajets"),
                ],
              ),
              const SizedBox(height: 14),

              // ── Légende statuts ─────────────────────────────────────────────────
              Row(
                children: [
                  _statusLegendDot(color: AppColors.gold, label: "À venir"),
                  const SizedBox(width: 12),
                  _statusLegendDot(color: Colors.white70, label: "Effectués"),
                  const SizedBox(width: 12),
                  _statusLegendDot(color: Colors.white38, label: "Annulés"),
                ],
              ),
              const SizedBox(height: 14),

              // ── Onglets + contenu ───────────────────────────────────────────────
              DefaultTabController(
                length: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barre segmentée premium
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0x12121212),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Lux.gold1.withOpacity(.10),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFE08A), Color(0xFFA87C00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Lux.gold1.withOpacity(.35),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          letterSpacing: .2,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        tabs: [
                          _luxTab("À venir", upcoming.length),
                          _luxTab("Effectués", done.length),
                          _luxTab("Annulés", canceled.length),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Contenu
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: TabBarView(
                        children: pages.entries.map((entry) {
                          final label = entry.key;
                          final list = entry.value;

                          if (list.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inbox_rounded,
                                      color: Colors.white24, size: 36),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Aucun trajet $label.",
                                    style:
                                        const TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF0D0D0D), Color(0xFF151515)],
                              ),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              itemCount: list.length,
                              itemBuilder: (context, i) => FadeInUp(
                                from: 12,
                                duration: const Duration(milliseconds: 300),
                                child: _tripCard(context, list[i]),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Tab _luxTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.black.withOpacity(.10),
              border: Border.all(color: Colors.black.withOpacity(.15)),
            ),
            child: Text(
              "$count",
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black, // lisible quand l’onglet est sélectionné
              ),
            ),
          ),
        ],
      ),
    );
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
          continue; // garder aujourd'hui

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

  // ── Normalisation / compat véhicule ──────────────────────────────────────────

  String _normType(String? raw) {
    if (raw == null) return '';
    final s = raw.trim().toLowerCase();
    const map = {
      'berline': 'berlines',
      'berlines': 'berlines',
      'moto': 'motos',
      'motos': 'motos',
      'van standing': 'vans standing',
      'vans standing': 'vans standing',
      'classe s': 'classe s',
      'classe e': 'classe e',
    };
    return map[s] ?? s;
  }

  Set<String> _requestedTypesFromReservation(Map<String, dynamic> data) {
    final out = <String>{};

    // 1) Champ canonique
    final req = _normType(data['requestedVehicleType'] as String?);
    if (req.isNotEmpty) out.add(req);

    // 2) Liste alternative
    final dynList = data['allowedVehicleTypes'];
    if (dynList is List) {
      for (final e in dynList) {
        if (e is String && e.trim().isNotEmpty) out.add(_normType(e));
      }
    }

    // 3) Rétro-compat (UI / anciens champs)
    for (final key in const ['vehicleType', 'vehicle', 'category']) {
      final v = _normType(data[key] as String?);
      if (v.isNotEmpty) out.add(v);
    }

    return out;
  }

  bool _vehicleMatch(String? driverVehicleType, Set<String> requested) {
    final d = _normType(driverVehicleType);
    if (d.isEmpty) return false; // un driver sans type n’est pas éligible
    if (requested.isEmpty) return true; // aucune contrainte côté résa → OK
    return requested.contains(d);
  }

  // ── Firestore fetchers ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRecentFeedbacks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      // 1) Base query
      Query<Map<String, dynamic>> baseQ = FirebaseFirestore.instance
          .collection('feedbacks')
          .where('driverId', isEqualTo: uid)
          .where('fromDriver', isEqualTo: false);

      // 2) orderBy si index, sinon fallback
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

      // 3) Prépare IDs
      final passengerIds = <String>{};
      final reservationIds = <String>{};
      for (final d in fbDocs) {
        final data = d.data();
        final pid = data['passengerId'] as String?;
        final rid = data['reservationId'] as String?;
        if (pid != null && pid.isNotEmpty) passengerIds.add(pid);
        if (rid != null && rid.isNotEmpty) reservationIds.add(rid);
      }

      // helper fetchByIds
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

      // 4) Chargements liés
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

      // 5) Construit liste enrichie
      final result = <Map<String, dynamic>>[];
      for (final doc in fbDocs) {
        final fb = doc.data();
        final pid = fb['passengerId'] as String?;
        final rid = fb['reservationId'] as String?;

        final user = (pid != null) ? usersById[pid] : null;
        final res = (rid != null) ? reservationsById[rid] : null;

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
    return _LuxNearbyButton(
      onTap: () => showNearbyCoursesDialog(context),
      label: "Voir les courses proches",
      icon: Icons.map_rounded,
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
                                      // Nouveau : chip countdown (sans changer la logique)
                                      Lux.countdownChip(duration,
                                          urgent: isUrgent),
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return [];

      // 1) Contexte conducteur : visible + type véhicule
      final driverDoc =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
      if (!driverDoc.exists) {
        debugPrint("⛔ Driver introuvable");
        return [];
      }
      final driver = driverDoc.data()!;
      final bool isVisible = (driver['isVisible'] as bool?) ?? false;
      if (!isVisible) {
        debugPrint("🔕 Driver hors ligne → pas de suggestions");
        return [];
      }
      final String? driverVehicleType =
          (driver['vehicleType'] as String?)?.trim();

      // 2) Position actuelle (si KO → on ne fait pas le filtre distance)
      Position? currentPosition;
      try {
        currentPosition = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint("⚠️ Géoloc indisponible (filtre distance désactivé) : $e");
      }

      // 3) Récup résas en attente
      final querySnapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('status', isEqualTo: 'En attente')
          .limit(100)
          .get();

      // 4) Filtrage distance + véhicule (client-side)
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // ---- Filtre véhicule (avec rétro-compat)
        final requested = _requestedTypesFromReservation(data);
        final bool vehicleOk = _vehicleMatch(driverVehicleType, requested);

        if (!vehicleOk) {
          debugPrint("🚫 ${doc.id} filtrée (vehicule) — "
              "requested=${requested.toList()} driver=$driverVehicleType");
          continue;
        }

        // ---- Filtre distance
        final fromLat = data['fromLat'] as num?;
        final fromLng = data['fromLng'] as num?;
        if (currentPosition != null) {
          if (fromLat == null || fromLng == null) {
            debugPrint(
                "⛔ Coordonnées manquantes pour ${data['from'] ?? 'Adresse'} → ignorée");
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
        } else {
          // Pas de géoloc → on ne filtre pas à la distance (fallback)
          nearby.add(doc);
        }
      }

      // 5) Tri par timestamp si présent
      nearby.sort((a, b) {
        final ta =
            (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
        final tb =
            (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });

      debugPrint(
          "✅ Nearby conservées: ${nearby.length} / total: ${querySnapshot.docs.length}");
    } catch (e, st) {
      debugPrint("❌ Erreur _fetchNearbyPendingReservations: $e\n$st");
    }

    return nearby;
  }

  Future<void> _acceptReservation(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Utilisateur non connecté");

    final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
    final driverSnap = await driverRef.get();
    if (!driverSnap.exists) {
      throw Exception("Conducteur non trouvé dans Firestore");
    }

    final driver = driverSnap.data()!;
    final firstName = (driver['firstName'] ?? 'Prénom').toString();
    final lastName = (driver['lastName'] ?? 'Nom').toString();
    final driverName = "$firstName $lastName";
    final vehicle =
        (driver['vehicle'] ?? driver['vehicleName'] ?? 'Véhicule inconnu')
            .toString();
    final String? driverVehicleType =
        (driver['vehicleType'] as String?)?.trim();

    final reservationRef =
        FirebaseFirestore.instance.collection('reservations').doc(docId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(reservationRef);
      if (!snap.exists) throw Exception("Réservation introuvable");

      final data = snap.data() as Map<String, dynamic>;
      final String status = (data['status'] ?? '').toString();
      if (status != 'En attente') {
        throw Exception("Réservation déjà prise (status=$status).");
      }

      // Revalider le type véhicule à l’acceptation
      final requested = _requestedTypesFromReservation(data);
      final bool vehicleOk = _vehicleMatch(driverVehicleType, requested);
      if (!vehicleOk) {
        throw Exception("Type de véhicule incompatible "
            "(demandé=${requested.toList()}, driver=$driverVehicleType)");
      }

      tx.update(reservationRef, {
        'status': 'Confirmée',
        'driverId': uid,
        'driverName': driverName,
        'vehicle': vehicle,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
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
        duration: const Duration(milliseconds: 260), // ✅ au lieu de 260.ms
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.black,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.gold : Colors.white12,
            width: selected ? 1.6 : 1,
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
            Expanded(child: Lux.goldGradientText('Espace conducteur', fs: 22)),
            const SizedBox(width: 8),
            Lux.goldSwitchChip(
              value: _isVisible,
              onChanged: _toggleVisibility,
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
            // ── Header mobile-first : salutation + capsule gains
            LayoutBuilder(
              builder: (context, c) {
                final isNarrow = c.maxWidth < 420; // breakpoint mobile étroit
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
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
                              const SizedBox(height: 4),
                              Lux.goldGradientText(
                                "${user?.firstName ?? 'Conducteur'} 👋",
                                fs: 22,
                              ),
                            ],
                          ),
                        ),
                        if (!isNarrow) const SizedBox(width: 12),
                        if (!isNarrow)
                          Lux.heroEarningCapsule(_formatEuroFr(_todayEarnings)),
                      ],
                    ),
                    if (isNarrow) ...[
                      const SizedBox(height: 12),
                      Lux.heroEarningCapsule(_formatEuroFr(_todayEarnings),
                          center: true),
                    ],
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
                ? [Pulse(infinite: true, child: _buildNearbyButton())]
                : _nearbyReservations.isEmpty
                    ? [_buildNearbyButton()]
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
                                        children: [
                                          const Icon(Icons.route,
                                              color: AppColors.gold, size: 18),
                                          const SizedBox(width: 6),
                                          const Text("Trajet",
                                              style: TextStyle(
                                                  color: AppColors.gold,
                                                  fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          Lux.countdownChip(diff,
                                              urgent: isUrgent),
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

// ── Trajets classés par statut — ULTRA PREMIUM
            _buildTripsSection(),
            const SizedBox(height: 24),

            const SizedBox(height: 24),
            _buildStatsSection(),
            const SizedBox(height: 24),
            _buildRevenueChart(),

            const SizedBox(height: 24),

            // ⭐️ — AVIS PASSAGERS PREMIUM
            FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchRecentFeedbacks(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }

                final feedbacks = _getFilteredFeedbacks();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 28),
                    Lux.glassCard(
                      title: "Avis de vos passagers ✨",
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sous-titre (on le place dans le child ici)
                          const Text(
                            "Votre réputation se construit ici",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 🔸 FILTRES
                          AnimatedSwitcher(
                            duration: const Duration(
                                milliseconds: 400), // ✅ au lieu de 400.ms
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final n in [null, 5, 4, 3, 2, 1])
                                  _reviewFilterChip(
                                    label: n == null
                                        ? "Tous"
                                        : "$n étoile${n > 1 ? "s" : ""}",
                                    selected: _starFilter == n,
                                    onTap: () =>
                                        setState(() => _starFilter = n),
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          _ratingDistribution(_feedbacks),
                          const SizedBox(height: 20),

                          // LISTE DES AVIS
                          ...feedbacks.asMap().entries.map((entry) {
                            final fb = entry.value;
                            final passenger =
                                (fb['passengerName'] ?? "Passager").toString();
                            final comment = fb['comment'] ?? "";
                            final rating =
                                (fb['rating'] as num?)?.toDouble() ?? 0.0;
                            final date =
                                (fb['timestamp'] as Timestamp?)?.toDate();
                            final from = fb['from']?.toString();
                            final to = fb['to']?.toString();

                            return _buildReviewTile(
                              name: passenger,
                              rating: rating,
                              comment: comment,
                              date: date,
                              from: from,
                              to: to,
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Voir profil
            _viewProfileButton(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _viewProfileButton() {
    return GestureDetector(
      onTap: () => context.go('/driver-profile'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFFFE08A), // Gold soft
              Color(0xFFA87C00), // Gold deep
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(.35),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Halo
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withOpacity(.25),
                      Colors.transparent
                    ],
                    radius: .85,
                  ),
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon capsule
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.15),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.black,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 12),

                const Text(
                  "Voir mon profil",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
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

        final w = snapshot.data!;

        final leftCapsule = TweenAnimationBuilder<double>(
          tween: Tween(begin: .0, end: 1.0),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) {
            return Container(
              width: 132,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF111111), Color(0xFF171717)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Lux.gold1.withOpacity(.12 * t),
                    blurRadius: 24 * t,
                    spreadRadius: 1,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.network(
                    w.iconUrl,
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.wb_cloudy, color: Colors.white38),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    w.city,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      colors: [Lux.gold1, Lux.gold2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(r),
                    child: Text(
                      "${w.temperature.toStringAsFixed(1)}°C",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

        final rightMetrics = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Lux.metric("🌥️", w.condition),
            const SizedBox(height: 12),
            Lux.metric("💨", "${w.windSpeed} km/h"),
            const SizedBox(height: 12),
            Lux.metric("💧", "${w.humidity} %"),
          ],
        );

        // ✅ Correct (pas d’argument "title")
        return Lux.goldGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Météo à ${w.city}",
                style: Lux.goldLabel(14),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leftCapsule,
                  const SizedBox(width: 18),
                  Expanded(child: rightMetrics),
                ],
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
        return Lux.goldGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Titre premium
              Row(
                children: [
                  Expanded(
                      child: Lux.goldGradientText("Mes statistiques", fs: 18)),
                ],
              ),
              const SizedBox(height: 14),

              // Tuiles stats ultra premium
              Row(
                children: [
                  Expanded(
                    child: _luxStatTile(
                      icon: Icons.directions_car,
                      label: "Trajets",
                      value: _countUpInt(stats.nbTrajets),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _luxStatTile(
                      icon: Icons.map_rounded,
                      label: "Kilomètres",
                      value: _countUpInt(stats.totalKm, suffix: " km"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _luxStatTile(
                      icon: Icons.star_rounded,
                      label: "Note",
                      value: _countUpDouble(stats.note, digits: 1),
                      highlight: true,
                    ),
                  ),
                ],
              ),
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

  /// Tuile stat luxueuse : verre fumé + bordure or + médaillon d’icône
  // Remplace ta version de _luxStatTile par celle-ci
  Widget _luxStatTile({
    required IconData icon,
    required String label,
    required Widget value,
    bool highlight = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 140;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E0E0E), Color(0xFF161616)],
            ),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Lux.gold1.withOpacity(.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Médaillon icône — taille plus petite en compact
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: highlight
                        ? [const Color(0xFFFFE08A), Lux.gold2]
                        : [const Color(0xFFE7C65C), const Color(0xFFB18C2D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Lux.gold1.withOpacity(.30),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child:
                      Icon(icon, size: compact ? 18 : 22, color: Colors.black),
                ),
              ),
              const SizedBox(width: 10),

              // Valeur + label — prennent tout l’espace restant
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // value est déjà un widget animé : on l’empêche d’overflow ici
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: value,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: compact ? 12 : 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ),

              if (highlight && !compact)
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Lux.gold1,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Lux.gold1.withOpacity(.7),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Compteur entier animé (ex: 0 → nbTrajets)
  /// Compteur entier animé (anti-overflow)
// Remplace tes _countUpInt / _countUpDouble par ces versions

  /// Compteur entier animé – s’adapte à la largeur (cache suffixe si nécessaire)
  Widget _countUpInt(int target, {String suffix = ""}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSuffix = constraints.maxWidth > 90 && suffix.isNotEmpty;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target.toDouble()),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, value, __) {
            final v = value.round();
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "$v",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                    ),
                  ),
                  if (showSuffix) const TextSpan(text: " "),
                  if (showSuffix)
                    TextSpan(
                      text: suffix,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      },
    );
  }

  /// Compteur décimal animé – adaptatif (anti-overflow, étoile masquée si étroit)
  Widget _countUpDouble(double target, {int digits = 1}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showStar =
            constraints.maxWidth > 90; // cache l'étoile si trop serré

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: target),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, value, __) {
            final txt = value.toStringAsFixed(digits);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      txt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ),
                if (showStar) const SizedBox(width: 6),
                if (showStar)
                  const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
              ],
            );
          },
        );
      },
    );
  }

  // Format court premium (k€) — ex: 7330 -> "7.3 k€"
  String _formatEuroShort(double value, {bool noSymbol = false}) {
    if (value >= 1000) {
      final v = (value / 1000);
      final s = v.toStringAsFixed(v < 10 ? 1 : 0);
      return noSymbol ? "$s k" : "$s k€";
    }
    final s = value.toStringAsFixed(0);
    return noSymbol ? s : "$s€";
  }

// Capsule tendance (mois courant vs mois précédent)
  Widget _trendChip({required double current, required double previous}) {
    double pct;
    if (previous <= 0 && current <= 0) {
      pct = 0;
    } else if (previous <= 0) {
      pct = 100;
    } else {
      pct = ((current - previous) / previous) * 100.0;
    }

    final up = pct >= 0;
    final txt =
        "${up ? "+" : ""}${pct.isFinite ? pct.toStringAsFixed(0) : '0'}%";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: up ? const Color(0xFF143C2B) : const Color(0xFF3C1A1A),
        border: Border.all(
            color: up ? const Color(0xFF1DBE74) : const Color(0xFFE05E5E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: up ? const Color(0xFF1DBE74) : const Color(0xFFE05E5E)),
          const SizedBox(width: 6),
          Text(
            txt,
            style: TextStyle(
              color: up ? const Color(0xFF86F0C0) : const Color(0xFFFF9A9A),
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
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

        return Lux.goldGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header luxe : titre + total annuel + tendance
              Row(
                children: [
                  Expanded(
                      child: Lux.goldGradientText("Mes revenus (12 mois)",
                          fs: 18)),
                  const SizedBox(width: 10),
                  _goldBadge(_formatEuroShort(
                    revenues.values.fold<double>(0.0, (a, b) => a + b),
                  )),
                  const SizedBox(width: 8),
                  _trendChip(
                    current: revenues[DateTime.now().month] ?? 0.0,
                    previous: revenues[(DateTime.now().month - 1) == 0
                            ? 12
                            : (DateTime.now().month - 1)] ??
                        0.0,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Graphique
              SizedBox(
                height: 220,
                child: BarChart(
                  BarChartData(
                    backgroundColor: Colors.transparent,
                    maxY: bgMaxY,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final i = group.x.toInt().clamp(0, 11);
                          return BarTooltipItem(
                            "${months[i]} • ${rod.toY.toStringAsFixed(0)}€",
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, _) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              _formatEuroShort(value, noSymbol: true),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            final i = value.toInt().clamp(0, 11);
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                months[i],
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: Colors.white10,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(12, (i) {
                      final revenue = revenues[i + 1] ?? 0.0;
                      return BarChartGroupData(
                        x: i,
                        barsSpace: 2,
                        barRods: [
                          BarChartRodData(
                            toY: revenue,
                            width: 18,
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFFFE08A), // gold clair
                                Color(0xFFA87C00), // gold profond
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: Colors.black.withOpacity(.20), width: 1),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: bgMaxY,
                              color: Colors.white10,
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 650),
                  swapAnimationCurve: Curves.easeOutExpo,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // refonte “verre fumé” sans changer la signature
  Widget _infoCard({required String title, required Widget child}) {
    return Lux.glassCard(title: title, child: child);
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

class _LuxNearbyButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  const _LuxNearbyButton({
    required this.onTap,
    required this.label,
    required this.icon,
  });

  @override
  State<_LuxNearbyButton> createState() => _LuxNearbyButtonState();
}

class _LuxNearbyButtonState extends State<_LuxNearbyButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        Future.delayed(const Duration(milliseconds: 120),
            () => setState(() => _pressed = false));
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(42),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF6D96B), // gold 1
                Color(0xFFB18C2D), // gold 2
              ],
            ),
            boxShadow: [
              // Halo externe
              BoxShadow(
                color: const Color(0xFFF6D96B).withOpacity(.28),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              // Glow interne
              BoxShadow(
                color: Colors.black.withOpacity(.30),
                blurRadius: 14,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black,
                    Colors.black87,
                  ],
                ).createShader(rect),
                blendMode: BlendMode.srcATop,
                child: Icon(
                  widget.icon,
                  size: 22,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 12),

              // Text Luxe
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .3,
                  color: Colors.black,
                  fontFamily: "Poppins",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
