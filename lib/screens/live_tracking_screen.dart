// ========== LIVE TRACKING SCREEN ULTRA PREMIUM NOIR & OR
// (PRO + Choix Waze/Google + WakeLock + Anti-Back + Metrics fiables) ==========

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../themes/app_theme.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart'; // <-- ton service de l’étape 2

// 👉 API STRIPE (garde tes endpoints)
const String _VERIFY_BASE =
    'https://verifypaymentintent-eq3zpvqefq-ew.a.run.app';
const String _CAPTURE_BASE =
    'https://capturepaymentintent-eq3zpvqefq-ew.a.run.app';

// 👉 (Optionnel) tes Cloud Functions Directions/ETA
const String? _DIRECTIONS_FN = null; // ex: 'https://your-cloud-fn/directions'
const String? _ETA_FN = null; // ex: 'https://your-cloud-fn/eta'

// ——————————————————————————————————————————————————————————————
// Utils
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

double _bearing(LatLng a, LatLng b) {
  final lat1 = a.latitude * (math.pi / 180);
  final lat2 = b.latitude * (math.pi / 180);
  final dLon = (b.longitude - a.longitude) * (math.pi / 180);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.cos(lat2) -
      math.sin(lat1) * math.sin(lat2) * math.cos(dLon);
  final brng = math.atan2(y, x) * 180 / math.pi;
  return (brng + 360) % 360;
}

enum DriverPhase { toPickup, toDropoff, inProgress, finished }

// ——————————————————————————————————————————————————————————————
// Écran
class LiveTrackingScreen extends StatefulWidget {
  final String reservationId;
  const LiveTrackingScreen({super.key, required this.reservationId});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;

  // Positions & routing
  LatLng? _driverPosition;
  LatLng? _lastDriverPos;
  double _markerRotation = 0;
  LatLng? _destination; // dropoff par défaut; pickup si phase toPickup
  LatLng? _pickup;

  final PolylinePoints _polylinePoints = PolylinePoints();
  final String _googleApiKey =
      "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI"; // fallback local si pas de Cloud Fn
  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};

  // Distances / ETA
  double _remainingDistanceKm = 0;
  double _estimatedDurationMin = 0;
  bool _hasMetrics = false; // 👉 pour éviter 0.0/0 min : "Calcul en cours…"

  // Phase métier
  DriverPhase _phase = DriverPhase.toPickup;

  // Streams
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot>? _reservationListener;

  // Icônes & halo
  BitmapDescriptor? _carIcon;
  late AnimationController _haloController;
  late Animation<double> _haloAnimation;
  Offset? _driverHaloOffset;

  // Animation déplacement
  late AnimationController _moveCtrl;
  Animation<LatLng>? _moveTween;
  VoidCallback? _animListener;

  // Throttling
  DateTime _lastRouteFetch = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _routeAnchor;
  static const _routeMinInterval = Duration(seconds: 20);
  static const _recalcDeviationMeters = 80;

  // Paiement overlay fin
  bool _showTripEndedOverlay = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // ✅ anti-veille pendant la course
    _loadCarIcon();

    _moveCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));

    _haloController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _haloAnimation = Tween<double>(begin: 22, end: 42).animate(
        CurvedAnimation(parent: _haloController, curve: Curves.easeInOut));

    _ensureSeedPosition().then((_) {
      // une fois la position initiale connue, on lance le stream
      _startLocationStream();
      _loadReservation();
      _listenStatus();
    });
  }

  // ——————————————————————————————————————————————————————————————
  // Seed position: évite Distance/ETA à 0 au démarrage
  Future<void> _ensureSeedPosition() async {
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      _driverPosition = LatLng(pos.latitude, pos.longitude);
      _lastDriverPos = _driverPosition;
      setState(() {});
    } catch (_) {
      // pas bloquant
    }
  }

  // ——————————————————————————————————————————————————————————————
  // LISTEN RESERVATION STATUS & TARGETS
  void _listenStatus() {
    _reservationListener = FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final status = (data["status"] ?? "").toString();

      if (status == "En route") {
        _phase = DriverPhase.toPickup;
        final pl = data["pickupLocation"];
        if (pl != null) _pickup = LatLng(pl["lat"], pl["lng"]);
        _destination = _pickup;
      } else if (status == "En cours") {
        _phase = DriverPhase.toDropoff;
        final dl = data["dropoffLocation"];
        if (dl != null) _destination = LatLng(dl["lat"], dl["lng"]);
      } else if (status == "Terminée") {
        _phase = DriverPhase.finished;
      }

      if (status == "Annulée") {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("La course a été annulée.")),
        );
        context.go("/driver-home");
      }

      // recalcul immédiat si on a déjà la position
      _kickstartMetrics();
      setState(() {});
    });
  }

  // ——————————————————————————————————————————————————————————————
  // ICÔNE VOITURE
  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(52, 52)),
      "assets/icons/car_gold.png",
    );
  }

  // ——————————————————————————————————————————————————————————————
  // DEMARRER STREAM LOCALISATION
  void _startLocationStream() async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5, // m
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      final next = LatLng(pos.latitude, pos.longitude);

      // Push Firestore (léger throttle côté client)
      FirebaseFirestore.instance
          .collection("reservations")
          .doc(widget.reservationId)
          .update({
        "driverLocation": {"lat": pos.latitude, "lng": pos.longitude}
      });

      _onNewPosition(next);
      _updateDistanceFallback();
      _maybeRefreshRoute();
      _softFollow();
      _updateHaloOffset();
    });
  }

  void _onNewPosition(LatLng next) {
    if (_lastDriverPos == null) {
      _lastDriverPos = next;
      _driverPosition = next;
      _markerRotation = 0;
      _kickstartMetrics();
      setState(() {});
      return;
    }

    _markerRotation = _bearing(_lastDriverPos!, next);

    _moveTween = LatLngTween(begin: _lastDriverPos!, end: next).animate(
      CurvedAnimation(parent: _moveCtrl, curve: Curves.easeInOut),
    );

    _animListener ??= () {
      _driverPosition = _moveTween!.value;
      setState(() {});
    };

    _moveCtrl
      ..removeListener(_animListener!)
      ..addListener(_animListener!)
      ..forward(from: 0);

    _lastDriverPos = next;
  }

  void _softFollow() {
    if (_mapController == null || _driverPosition == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _driverPosition!,
          zoom: 16.5,
          tilt: 35,
          bearing: _markerRotation,
        ),
      ),
    );
  }

  // ——————————————————————————————————————————————————————————————
  // LOAD RESERVATION (destinations)
  Future<void> _loadReservation() async {
    final snap = await FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .get();
    final data = snap.data();
    if (data == null) return;

    if (data["pickupLocation"] != null) {
      final p = data["pickupLocation"];
      _pickup = LatLng(p["lat"], p["lng"]);
    }
    if (data["dropoffLocation"] != null) {
      final d = data["dropoffLocation"];
      // Par défaut: on part vers le passager si pickup connu
      _destination = _pickup ?? LatLng(d["lat"], d["lng"]);
    }

    if (_mapController != null) _setMapStyle();

    _kickstartMetrics();
    setState(() {});
  }

  // Démarre le calcul dès qu’on a position + destination
  void _kickstartMetrics() {
    if (_driverPosition != null && _destination != null) {
      _maybeRefreshRoute();
      _updateDistanceFallback();
    }
  }

  // ——————————————————————————————————————————————————————————————
  // ROUTING (throttlé) : Cloud Fn si dispo, sinon PolylinePoints local
  Future<void> _maybeRefreshRoute() async {
    if (_driverPosition == null || _destination == null) return;
    final now = DateTime.now();
    final since = now.difference(_lastRouteFetch);
    final deviated = _routeAnchor == null
        ? true
        : Geolocator.distanceBetween(
                _driverPosition!.latitude,
                _driverPosition!.longitude,
                _routeAnchor!.latitude,
                _routeAnchor!.longitude) >
            _recalcDeviationMeters;

    if (since < _routeMinInterval && !deviated) return;

    _lastRouteFetch = now;
    _routeAnchor = _driverPosition;

    if (_DIRECTIONS_FN != null) {
      try {
        final resp = await http
            .post(Uri.parse(_DIRECTIONS_FN!),
                headers: {"Content-Type": "application/json"},
                body: json.encode({
                  "origin": {
                    "lat": _driverPosition!.latitude,
                    "lng": _driverPosition!.longitude
                  },
                  "destination": {
                    "lat": _destination!.latitude,
                    "lng": _destination!.longitude
                  },
                  "mode": "driving"
                }))
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final m = json.decode(resp.body) as Map<String, dynamic>;
          final pts = (m["polyline"] as List).cast<List>();
          _polylineCoordinates =
              pts.map((e) => LatLng(e[0] as double, e[1] as double)).toList();
          _applyPolyline();
        } else {
          await _refreshPolylineFallback();
        }
      } catch (_) {
        await _refreshPolylineFallback();
      }

      if (_ETA_FN != null) {
        try {
          final resp = await http
              .post(Uri.parse(_ETA_FN!),
                  headers: {"Content-Type": "application/json"},
                  body: json.encode({
                    "origin": {
                      "lat": _driverPosition!.latitude,
                      "lng": _driverPosition!.longitude
                    },
                    "destination": {
                      "lat": _destination!.latitude,
                      "lng": _destination!.longitude
                    }
                  }))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final m = json.decode(resp.body) as Map<String, dynamic>;
            _remainingDistanceKm =
                ((m["distance_meters"] ?? 0) as num).toDouble() / 1000.0;
            _estimatedDurationMin =
                ((m["duration_minutes"] ?? 0) as num).toDouble();
            _hasMetrics = true;
            setState(() {});
          } else {
            _updateDistanceFallback();
          }
        } catch (_) {
          _updateDistanceFallback();
        }
      }
    } else {
      await _refreshPolylineFallback();
      _updateDistanceFallback();
    }
  }

  Future<void> _refreshPolylineFallback() async {
    if (_driverPosition == null || _destination == null) return;
    final pts = await _polylinePoints.getRouteBetweenCoordinates(
      _googleApiKey,
      PointLatLng(_driverPosition!.latitude, _driverPosition!.longitude),
      PointLatLng(_destination!.latitude, _destination!.longitude),
      travelMode: TravelMode.driving,
    );
    if (pts.points.isNotEmpty) {
      _polylineCoordinates =
          pts.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      _applyPolyline();
    }
  }

  void _applyPolyline() {
    _polylines = {
      Polyline(
        polylineId: const PolylineId("route"),
        color: AppColors.gold,
        width: 6,
        points: _polylineCoordinates,
      ),
    };
    setState(() {});
  }

  // Fallback ETA local (lisible, jamais 0)
  void _updateDistanceFallback() {
    if (_driverPosition == null || _destination == null) return;

    final meters = Geolocator.distanceBetween(
      _driverPosition!.latitude,
      _driverPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    // Distance en km avec plancher
    _remainingDistanceKm = (meters / 1000).clamp(0.0, double.infinity);

    // approx 30 km/h → 0.5 km/min, marge 20%, minimum 1 minute
    final estMin = (((_remainingDistanceKm) / 0.5) * 1.2);
    _estimatedDurationMin = estMin < 1 && meters > 30 ? 1 : estMin;

    _hasMetrics = true;
    setState(() {});
  }

  // ——————————————————————————————————————————————————————————————
  // STYLE MAP NOIR
  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString("assets/map_style_dark.json");
    _mapController?.setMapStyle(style);
  }

  // ——————————————————————————————————————————————————————————————
  // HALO centré sur la voiture (coordonnées écran)
  Future<void> _updateHaloOffset() async {
    if (_mapController == null || _driverPosition == null) return;
    try {
      final sc = await _mapController!.getScreenCoordinate(_driverPosition!);
      _driverHaloOffset = Offset(sc.x.toDouble(), sc.y.toDouble());
    } catch (_) {}
  }

  // ——————————————————————————————————————————————————————————————
  // FIN DE TRAJET → PAIEMENT + OVERLAY
  Future<void> _endTrip() async {
    final docRef = FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId);

    await docRef.update({
      "status": "Terminée",
      "completedAt":
          FieldValue.serverTimestamp(), // ✅ champ attendu par les stats
      "endTime": FieldValue.serverTimestamp(),
    });

    // Paiement (retry léger local)
    final snap = await docRef.get();
    final data = snap.data();
    final String? pi = data?["paymentIntentId"];

    if (pi != null && pi.isNotEmpty) {
      final paymentStatus = data?["paymentStatus"];
      if (paymentStatus != "succeeded") {
        await docRef.update({"paymentStatus": "capture_pending"});
        final tries = [0, 800, 1600];
        for (final delayMs in tries) {
          if (delayMs > 0)
            await Future.delayed(Duration(milliseconds: delayMs));
          final ok = await _verifyAndCapture(pi, docRef);
          if (ok) break;
        }
      }
    }

    if (mounted) {
      setState(() => _showTripEndedOverlay = true);
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) context.go("/feedback-driver/${widget.reservationId}");
    }
  }

  Future<bool> _verifyAndCapture(
      String pi, DocumentReference<Map<String, dynamic>> docRef) async {
    try {
      final verifyUri = Uri.parse("$_VERIFY_BASE?pi=$pi");
      final verifyResp =
          await http.get(verifyUri).timeout(const Duration(seconds: 20));
      if (verifyResp.statusCode != 200) return false;

      final v = json.decode(verifyResp.body) as Map<String, dynamic>;
      final st = (v["status"] ?? "").toString();

      if (st == "requires_capture") {
        final capUri = Uri.parse("$_CAPTURE_BASE?pi=$pi");
        final capResp =
            await http.get(capUri).timeout(const Duration(seconds: 20));

        if (capResp.statusCode == 200) {
          final c = json.decode(capResp.body) as Map<String, dynamic>;
          await docRef.update({
            "paymentStatus": c["status"],
            "amountReceived": c["amount"],
            "currency": c["currency"],
            "capturedAt": FieldValue.serverTimestamp(),
          });
          return true;
        } else {
          await docRef.update({
            "paymentStatus": "capture_error",
            "captureError": capResp.body,
          });
          return false;
        }
      }
      return st == "succeeded";
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // ✅ on rend la main au système
    _positionStream?.cancel();
    _reservationListener?.cancel();
    _moveCtrl.dispose();
    _haloController.dispose();
    super.dispose();
  }

  // ======================================================================
  // UI
  @override
  Widget build(BuildContext context) {
    final bool canLeave =
        _phase == DriverPhase.finished || _showTripEndedOverlay;

    return WillPopScope(
      // ✅ bloque le back tant que la course n’est pas finie
      onWillPop: () async {
        if (canLeave) return true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Termine la course pour quitter cet écran.")),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: Stack(
          children: [
            if (_driverPosition != null)
              GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: _driverPosition!, zoom: 15),
                myLocationEnabled: false,
                polylines: _polylines,
                markers: {
                  Marker(
                    markerId: const MarkerId("driver"),
                    position: _driverPosition!,
                    rotation: _markerRotation,
                    flat: true,
                    anchor: const Offset(0.5, 0.5),
                    icon: _carIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueYellow),
                  ),
                  if (_destination != null)
                    Marker(
                      markerId: const MarkerId("dest"),
                      position: _destination!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure),
                    ),
                },
                onMapCreated: (c) {
                  _mapController = c;
                  _setMapStyle();
                },
                onCameraMove: (_) => _updateHaloOffset(),
              ),

            // Bouton flottant “Naviguer”
            if (_destination != null && !_showTripEndedOverlay)
              Positioned(
                right: 16,
                bottom: 92, // au-dessus du HUD
                child: FloatingActionButton.extended(
                  heroTag: "nav_fab",
                  onPressed: () => showNavigationChooser(
                    context,
                    destLat: _destination!.latitude,
                    destLng: _destination!.longitude,
                    origin: _driverPosition,
                  ),
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text(
                    "Naviguer",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),

            // Halo animé
            if (_driverHaloOffset != null)
              AnimatedBuilder(
                animation: _haloAnimation,
                builder: (_, __) {
                  final size = MediaQuery.of(context).size;
                  final clampedX = _driverHaloOffset!.dx
                      .clamp(0.0, size.width - _haloAnimation.value);
                  final clampedY = _driverHaloOffset!.dy
                      .clamp(0.0, size.height - _haloAnimation.value);
                  return Positioned(
                    left: clampedX - _haloAnimation.value / 2,
                    top: clampedY - _haloAnimation.value / 2,
                    child: Container(
                      width: _haloAnimation.value,
                      height: _haloAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.gold.withOpacity(.25),
                      ),
                    ),
                  );
                },
              ),

            if (_showTripEndedOverlay) _buildEndOverlay(),

            if (!_showTripEndedOverlay) _buildHUD(context),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // HUD
  String get _phaseTitle {
    switch (_phase) {
      case DriverPhase.toPickup:
        return "Vers le passager";
      case DriverPhase.toDropoff:
        return "En route vers la destination";
      case DriverPhase.inProgress:
        return "Course en cours";
      case DriverPhase.finished:
        return "Course terminée";
    }
  }

  String _humanizeDistance() {
    if (!_hasMetrics) return "Calcul en cours…";
    final km = _remainingDistanceKm;
    if (km < 1) {
      final m = (km * 1000).round();
      return "$m m";
    }
    return "${km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0)} km";
  }

  String _humanizeEta() {
    if (!_hasMetrics) return "Calcul en cours…";
    final mins =
        _estimatedDurationMin.isFinite ? _estimatedDurationMin : 0; // sécurité
    final rounded = mins < 1 ? 1 : mins.round();
    return "~ $rounded min";
  }

  Widget _buildHUD(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _buildGlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title("🟡 $_phaseTitle"),
                const SizedBox(height: 6),
                _info("Distance : ${_humanizeDistance()}"),
                _info("Estimation : ${_humanizeEta()}"),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_destination != null)
                      _goldButton(
                        label: "Naviguer",
                        icon: Icons.directions_rounded,
                        onTap: () => showNavigationChooser(
                          context,
                          destLat: _destination!.latitude,
                          destLng: _destination!.longitude,
                          origin: _driverPosition,
                        ),
                      ),
                    const Spacer(),
                    FloatingActionButton.extended(
                      onPressed: _endTrip,
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                      icon: const Icon(Icons.flag_circle_rounded),
                      label: const Text(
                        "Terminer",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: "PlayfairDisplay",
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ======================================================================
  // OVERLAY FIN
  Widget _buildEndOverlay() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 900),
      opacity: 1,
      child: Container(
        color: AppColors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 110),
            const SizedBox(height: 20),
            Text(
              "Course terminée",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: "PlayfairDisplay",
                color: AppColors.gold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Merci pour votre conduite ✨",
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ======================================================================
  // UI ATOMS
  Widget _buildGlassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold.withOpacity(.3)),
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withOpacity(.65),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.15),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _title(String t) => Text(
        t,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 17,
          fontFamily: "PlayfairDisplay",
          fontWeight: FontWeight.bold,
        ),
      );

  Widget _info(String t) => Text(
        t,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
        ),
      );

  Widget _goldButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.black),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}

// ======================================================================
// Sélecteur d’app de navigation (bottom sheet premium / dialog Web)
Future<void> showNavigationChooser(
  BuildContext context, {
  required double destLat,
  required double destLng,
  LatLng? origin,
}) async {
  Future<void> _open(NavApp app) async {
    await openExternalNavigation(
      destLat: destLat,
      destLng: destLng,
      origin: origin,
      prefer: app,
    );
  }

  final content = (BuildContext ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: const [
              Icon(Icons.near_me_rounded, color: Colors.white70),
              SizedBox(width: 8),
              Text(
                "Choisir l’app de navigation",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _NavOption(
            icon: Icons.map_rounded,
            label: "Google Maps",
            onTap: () async {
              Navigator.of(ctx).maybePop();
              await _open(NavApp.googleMaps);
            },
          ),
          const SizedBox(height: 8),
          _NavOption(
            icon: Icons.navigation_rounded,
            label: "Waze",
            onTap: () async {
              Navigator.of(ctx).maybePop();
              await _open(NavApp.waze);
            },
          ),
        ],
      );

  if (kIsWeb) {
    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child:
              Padding(padding: const EdgeInsets.all(16), child: content(ctx)),
        );
      },
    );
  } else {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
          child:
              Padding(padding: const EdgeInsets.all(16), child: content(ctx))),
    );
  }
}

class _NavOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// NAVIGATION EXTERNE (Android / iOS / Web + fallbacks)
enum NavApp { googleMaps, waze }

Future<void> openExternalNavigation({
  required double destLat,
  required double destLng,
  LatLng? origin,
  NavApp? prefer, // si null : essaie Google puis Waze
}) async {
  final hasOrigin = origin != null;
  final oLat = origin?.latitude;
  final oLng = origin?.longitude;

  // --- GOOGLE MAPS
  final gmAndroidIntent =
      Uri.parse("google.navigation:q=$destLat,$destLng&mode=d");
  final gmIOSScheme = Uri.parse(
      "comgooglemaps://?daddr=$destLat,$destLng&directionsmode=driving"
      "${hasOrigin ? "&saddr=$oLat,$oLng" : ""}");
  final gmWeb = Uri.parse("https://www.google.com/maps/dir/?api=1"
      "&destination=$destLat,$destLng"
      "${hasOrigin ? "&origin=$oLat,$oLng" : ""}&travelmode=driving");
  final appleMaps = Uri.parse("http://maps.apple.com/?daddr=$destLat,$destLng"
      "${hasOrigin ? "&saddr=$oLat,$oLng" : ""}&dirflg=d");

  // --- WAZE
  final wazeScheme = Uri.parse("waze://?ll=$destLat,$destLng&navigate=yes");
  final wazeWeb =
      Uri.parse("https://waze.com/ul?ll=$destLat,$destLng&navigate=yes");

  Future<bool> _launch(Uri u) async {
    if (await canLaunchUrl(u)) {
      return await launchUrl(u, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  // Ordre d’essai
  final order = prefer == NavApp.waze ? ["waze", "gm"] : ["gm", "waze"];

  for (final key in order) {
    if (key == "gm") {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          await _launch(gmAndroidIntent)) return;
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          await _launch(gmIOSScheme)) return;
      if (await _launch(gmWeb)) return;
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          await _launch(appleMaps)) return; // fallback iOS
    } else {
      if (await _launch(wazeScheme)) return;
      if (await _launch(wazeWeb)) return;
    }
  }

  debugPrint("❌ Aucune application de navigation disponible.");
}

// ======================================================================
// Compat ascendante : ancien helper
Future<void> openInNavigationApp(double lat, double lng,
    {bool useWaze = false}) async {
  await openExternalNavigation(
    destLat: lat,
    destLng: lng,
    prefer: useWaze ? NavApp.waze : NavApp.googleMaps,
  );
}
