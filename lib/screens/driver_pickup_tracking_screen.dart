// lib/screens/driver_pickup_tracking_screen.dart
// Driver → Pickup : suivi temps réel ULTRA PREMIUM (veille désactivée, ETA fiable, design luxe)

import 'dart:async';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'
    show rootBundle, SystemChrome, SystemUiMode;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../themes/app_theme.dart';

class DriverPickupTrackingScreen extends StatefulWidget {
  final String reservationId;

  const DriverPickupTrackingScreen({super.key, required this.reservationId});

  @override
  State<DriverPickupTrackingScreen> createState() =>
      _DriverPickupTrackingScreenState();
}

class _DriverPickupTrackingScreenState extends State<DriverPickupTrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;

  LatLng? _driverPosition;
  LatLng? _pickupLocation;

  BitmapDescriptor? _carIcon;

  StreamSubscription<Position>? _locationStream;

  final PolylinePoints _polylinePoints = PolylinePoints();
  final String _googleApiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI';

  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};

  double _remainingDistance = 0; // km
  double _estimatedDuration = 0; // minutes (approx)

  late AnimationController _haloController;
  late Animation<double> _haloAnimation;

  Timer? _softEtaTicker;

  // -------- Lifecycle --------
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // UX navigation : plein écran léger (status bar cachée) pour focus carte
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Évite la mise en veille pendant la navigation
    WakelockPlus.enable();

    _init();
  }

  Future<void> _init() async {
    await _ensureLocationReady();
    await _loadCarIcon();
    await _loadPickupData();
    _startLocationUpdates();

    // Halo doux (effet premium)
    _haloController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _haloAnimation = Tween<double>(begin: 18, end: 42).animate(
      CurvedAnimation(parent: _haloController, curve: Curves.easeInOut),
    );

    // ETA "souple" toutes les 5 s si on a les 2 points
    _softEtaTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_driverPosition != null && _pickupLocation != null) {
        _updateDistance(); // approx locale mais robuste
      }
    });
  }

  // Demande service + permissions localisation proprement
  Future<void> _ensureLocationReady() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // On ne bloque pas, mais on tente d’ouvrir les settings
      await Geolocator.openLocationSettings();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      // On n’a pas la main → on affiche une notice douce in-app
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Autorisez la localisation pour suivre l’itinéraire vers le passager.",
            ),
          ),
        );
      }
    }
  }

  // -------- Data initiale : pickup --------
  Future<void> _loadPickupData() async {
    final snap = await FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .get();

    final data = snap.data();
    if (data == null) return;

    if (data["pickupLocation"] != null) {
      final loc = data["pickupLocation"];
      _pickupLocation = LatLng(loc["lat"], loc["lng"]);

      // Si on a déjà la position driver (cache), on met à jour tout de suite
      _updateDistance();
      _refreshPolyline();
      setState(() {});
    }
  }

  // -------- Icône véhicule --------
  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      "assets/icons/car_gold.png",
    );
  }

  // -------- Stream position en continu --------
  void _startLocationUpdates() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // on réduit le bruit, mise à jour tous les 5 m
    );

    _locationStream =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _driverPosition = LatLng(pos.latitude, pos.longitude);

        // On ne recalcule que si le pickup est connu
        if (_pickupLocation != null) {
          _updateDistance();
          _refreshPolyline();
        }

        // Push Firestore (pour suivi passager/dispatch)
        FirebaseFirestore.instance
            .collection("reservations")
            .doc(widget.reservationId)
            .update({
          "driverLocation": {"lat": pos.latitude, "lng": pos.longitude}
        });

        // Caméra douce
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_driverPosition!),
        );

        setState(() {});
      },
      onError: (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Localisation indisponible : $e')),
          );
        }
      },
    );
  }

  // -------- Polyligne route driver → pickup --------
  Future<void> _refreshPolyline() async {
    if (_driverPosition == null || _pickupLocation == null) return;

    final result = await _polylinePoints.getRouteBetweenCoordinates(
      _googleApiKey,
      PointLatLng(_driverPosition!.latitude, _driverPosition!.longitude),
      PointLatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isEmpty) return;

    _polylineCoordinates =
        result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    _polylines = {
      Polyline(
        polylineId: const PolylineId("pickup"),
        points: _polylineCoordinates,
        color: AppColors.gold,
        width: 6,
      )
    };

    setState(() {});
  }

  // -------- Distance / ETA (approx robuste) --------
  void _updateDistance() {
    if (_driverPosition == null || _pickupLocation == null) return;

    final meters = Geolocator.distanceBetween(
      _driverPosition!.latitude,
      _driverPosition!.longitude,
      _pickupLocation!.latitude,
      _pickupLocation!.longitude,
    );

    // Heuristique douce : 36 km/h moyen urbain (~0.6 km/min), facteur 1.15
    final km = meters / 1000.0;
    final approxMinutes = max(1.0, (km / 0.6) * 1.15);

    setState(() {
      _remainingDistance = km;
      _estimatedDuration = approxMinutes;
    });
  }

  // -------- Carte style sombre --------
  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString("assets/map_style_dark.json");
    _mapController?.setMapStyle(style);
  }

  // -------- Actions --------
  Future<void> _confirmArrival() async {
    await FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .update({"status": "Arrivé"});

    if (mounted) context.go("/driver/trip/${widget.reservationId}");
  }

  void _recenterCamera() {
    if (_driverPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _driverPosition!, zoom: 15.5),
        ),
      );
    }
  }

  // -------- Clean-up --------
  @override
  void dispose() {
    _softEtaTicker?.cancel();
    _locationStream?.cancel();
    _haloController.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // -------- Reprise focus quand l’app revient au premier plan --------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // On remet la carte en style sombre et on recalcule
      _setMapStyle();
      _recenterCamera();
      _updateDistance();
      setState(() {});
    }
  }

  // ======================================================
  // ✅ ✅   UI ULTRA PREMIUM
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final canShowMap = _driverPosition != null;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          // MAP
          if (canShowMap)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _driverPosition!,
                zoom: 15.5,
                tilt: 0,
                bearing: 0,
              ),
              onMapCreated: (c) {
                _mapController = c;
                _setMapStyle();
              },
              myLocationEnabled: false,
              trafficEnabled: false,
              compassEnabled: false,
              zoomControlsEnabled: false,
              polylines: _polylines,
              markers: {
                Marker(
                  markerId: const MarkerId("driver"),
                  position: _driverPosition!,
                  icon: _carIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueYellow,
                      ),
                ),
                if (_pickupLocation != null)
                  Marker(
                    markerId: const MarkerId("pickup"),
                    position: _pickupLocation!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                  ),
              },
            ),

          // HALO premium (subtil)
          if (canShowMap)
            AnimatedBuilder(
              animation: _haloAnimation,
              builder: (_, __) {
                return Positioned(
                  top: MediaQuery.of(context).size.height / 2 -
                      _haloAnimation.value / 2 -
                      90,
                  left: MediaQuery.of(context).size.width / 2 -
                      _haloAnimation.value / 2,
                  child: Container(
                    width: _haloAnimation.value,
                    height: _haloAnimation.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold.withOpacity(.22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withOpacity(.28),
                          blurRadius: 14,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                );
              },
            ),

          // HUD haut (status pill)
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            left: 16,
            right: 16,
            child: _StatusPill(
              title: "Vers le passager",
              subtitle: _pickupLocation == null
                  ? "Initialisation de l’itinéraire…"
                  : "Navigation active",
            ),
          ),

          // HUD bas (infos & actions)
          _buildHUD(context),

          // Boutons flottants (recentrer + arriver)
          Positioned(
            bottom: 24,
            left: 24,
            child: _RoundGlassButton(
              icon: Icons.my_location_rounded,
              onTap: _recenterCamera,
            ),
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              onPressed: _confirmArrival,
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              elevation: 10,
              icon: const Icon(Icons.flag_rounded, size: 26),
              label: const Text(
                "Je suis arrivé",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: "PlayfairDisplay",
                  letterSpacing: .2,
                ),
              ),
            ),
          ),

          // Fallback si pas de GPS encore
          if (!canShowMap)
            const _CenteredLoader(message: "Localisation du véhicule…"),
        ],
      ),
    );
  }

  // ✅ HUD ULTRA PREMIUM
  Widget _buildHUD(BuildContext context) {
    final dist = _remainingDistance;
    final eta = _estimatedDuration;

    return Positioned(
      bottom: 110,
      left: 16,
      right: 16,
      child: _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle("🟡 En route vers le passager"),
            const SizedBox(height: 4),
            const Text(
              "Restez en mouvement, suivez la route recommandée.",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MetricTile(
                  label: "Distance",
                  value: dist > 0 ? "${dist.toStringAsFixed(1)} km" : "—",
                ),
                const SizedBox(width: 12),
                _MetricTile(
                  label: "Estimation",
                  value: eta > 0 ? "${eta.toStringAsFixed(0)} min" : "—",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Widgets premium (verre sombre, pills, metrics)
// ─────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold.withOpacity(.38), width: 1),
        borderRadius: BorderRadius.circular(20),
        color: Colors.black.withOpacity(.58),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.18),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String text;
  const _CardTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.gold,
        fontSize: 16,
        fontFamily: "PlayfairDisplay",
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF141414), Color(0xFF0E0E0E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontFamily: "PlayfairDisplay",
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.55),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: Icon(Icons.my_location_rounded, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String title;
  final String subtitle;
  const _StatusPill({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F0F0F), Color(0xFF1A1A1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.14),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontFamily: "PlayfairDisplay",
                      fontWeight: FontWeight.w800,
                    )),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  final String message;
  const _CenteredLoader({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.gold),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
