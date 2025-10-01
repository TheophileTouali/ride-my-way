// VERSION OPTIMISÉE DE LiveTrackingScreen (animation premium fin de trajet pour conducteur avec message personnalisé)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../themes/app_theme.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';


// 👉 ces constantes sont globales, accessibles partout dans ce fichier
const String _VERIFY_BASE =
    'https://verifypaymentintent-eq3zpvqefq-ew.a.run.app'; // GET ?pi=...
const String _CAPTURE_BASE =
    'https://capturepaymentintent-eq3zpvqefq-ew.a.run.app'; // GET ?pi=...

class LiveTrackingScreen extends StatefulWidget {
  final String reservationId;
  const LiveTrackingScreen({super.key, required this.reservationId});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  LatLng? _destination;
  BitmapDescriptor? _carIcon;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<DocumentSnapshot>? _reservationListener;
  late AnimationController _haloController;
  late Animation<double> _haloAnimation;

  double _remainingDistance = 0;
  double _estimatedDuration = 0;
  bool _showTripEndedMessage = false;

  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};
  final PolylinePoints _polylinePoints = PolylinePoints();
  final String _googleApiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI';

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
    _startLocationUpdates();
    _loadReservationData();
    _listenReservationStatus();

    _haloController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _haloAnimation = Tween<double>(begin: 20, end: 40).animate(_haloController);
  }

  void _listenReservationStatus() {
    _reservationListener = FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'];
      if (status == 'Annulée' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La course a été annulée.')),
        );
        context.go('/driver-home');
      }
    });
  }

  Future<void> _getRoutePolyline() async {
    if (_driverPosition == null || _destination == null) return;

    final result = await _polylinePoints.getRouteBetweenCoordinates(
      _googleApiKey,
      PointLatLng(_driverPosition!.latitude, _driverPosition!.longitude),
      PointLatLng(_destination!.latitude, _destination!.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      setState(() {
        _polylineCoordinates = result.points
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList();
        _polylines = {
          Polyline(
            polylineId: const PolylineId("route"),
            color: AppColors.gold,
            width: 5,
            points: _polylineCoordinates,
          ),
        };
      });
    }
  }

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/car_gold.png',
    );
    setState(() {});
  }

  void _startLocationUpdates() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high);
    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen((position) {
      final newPos = LatLng(position.latitude, position.longitude);
      final hasMoved = _driverPosition == null ||
          _driverPosition!.latitude != newPos.latitude ||
          _driverPosition!.longitude != newPos.longitude;

      setState(() => _driverPosition = newPos);

      FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .update({
        'driverLocation': {'lat': newPos.latitude, 'lng': newPos.longitude}
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
      _updateDistanceAndDuration();
      if (hasMoved) _getRoutePolyline();
    });
  }

  void _updateDistanceAndDuration() {
    if (_driverPosition != null && _destination != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _driverPosition!.latitude,
        _driverPosition!.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );

      setState(() {
        _remainingDistance = distanceInMeters / 1000;
        _estimatedDuration = (_remainingDistance / 0.5) * 1.2;
      });
    }
  }

  Future<void> _loadReservationData() async {
    final doc = await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .get();
    final data = doc.data();
    if (data != null && data['dropoffLocation'] != null) {
      final d = data['dropoffLocation'];
      setState(() => _destination = LatLng(d['lat'], d['lng']));
      _getRoutePolyline();
    }
  }

  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_dark.json');
    _mapController?.setMapStyle(style);
  }


Future<void> _endTrip() async {
  final docRef = FirebaseFirestore.instance
      .collection('reservations')
      .doc(widget.reservationId);

  // 1) Marquer la course terminée
  await docRef.update({
    'status': 'Terminée',
    'endTime': FieldValue.serverTimestamp(),
  });

  // 2) Récupérer le PaymentIntent ID
  final snap = await docRef.get();
  final String? pi = snap.data()?['paymentIntentId'];

  if (pi == null || pi.isEmpty) {
    debugPrint('⚠️ Aucun paymentIntentId sur la réservation.');
  } else {
    // 🔒 Sécurité anti double capture
    final currentPaymentStatus = snap.data()?['paymentStatus'] ?? '';
    if (currentPaymentStatus == 'succeeded') {
      debugPrint('ℹ️ Paiement déjà capturé en base (Firestore).');
    } else {
      await docRef.update({'paymentStatus': 'capture_pending'});

      try {
        // 3a) Vérifier l’état actuel du PI (utile si déjà capturé via dashboard ou lien direct)
        final verifyUri = Uri.parse('$_VERIFY_BASE?pi=$pi');
        final verifyResp =
            await http.get(verifyUri).timeout(const Duration(seconds: 20));

        if (verifyResp.statusCode == 200) {
          final v = json.decode(verifyResp.body) as Map<String, dynamic>;
          final currentStatus = (v['status'] as String?) ?? '';

          await docRef.update({
            'stripe': {
              'paymentIntentId': pi,
              'lastCheckedAt': FieldValue.serverTimestamp(),
            }
          });

          if (currentStatus == 'succeeded') {
            // Déjà capturé (ex: lien direct)
            await docRef.update({
              'paymentStatus': 'succeeded',
              'amountReceived': v['amount'],
              'currency': v['currency'],
              'capturedAt': FieldValue.serverTimestamp(),
            });
            debugPrint('ℹ️ PI déjà capturé côté Stripe ($pi).');
          } else if (currentStatus == 'requires_capture') {
            // 3b) Capturer maintenant
            final capUri = Uri.parse('$_CAPTURE_BASE?pi=$pi');
            final capResp =
                await http.get(capUri).timeout(const Duration(seconds: 20));

            if (capResp.statusCode == 200) {
              final c = json.decode(capResp.body) as Map<String, dynamic>;
              await docRef.update({
                'paymentStatus': c['status'], // attendu: 'succeeded'
                'amountReceived': c['amount'],
                'currency': c['currency'],
                'capturedAt': FieldValue.serverTimestamp(),
              });
              debugPrint('✅ Paiement capturé: $pi (${c['status']}).');
            } else {
              debugPrint('❌ Erreur capture Stripe: ${capResp.body}');
              await docRef.update({
                'paymentStatus': 'capture_error',
                'captureError': capResp.body,
                'captureErrorAt': FieldValue.serverTimestamp(),
              });
            }
          } else {
            // autre statut inattendu
            await docRef.update({
              'paymentStatus': currentStatus,
              'paymentStatusCheckedAt': FieldValue.serverTimestamp(),
            });
            debugPrint('⚠️ Statut PI inattendu: $currentStatus (pi=$pi).');
          }
        } else {
          debugPrint('❌ Vérification PI a échoué: ${verifyResp.body}');
        }
      } catch (e) {
        debugPrint('❌ Exception capture: $e');
        await docRef.update({
          'paymentStatus': 'capture_exception',
          'captureException': e.toString(),
          'captureErrorAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // 4) UI de fin + redirection
  if (mounted) {
    setState(() => _showTripEndedMessage = true);
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) context.go('/feedback-driver/${widget.reservationId}');
  }
}

  @override
  void dispose() {
    _positionStream?.cancel();
    _reservationListener?.cancel();
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: const Text("Suivi en direct"),
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
      ),
      body: Stack(
        children: [
          if (_driverPosition != null)
            GoogleMap(
              polylines: _polylines,
              initialCameraPosition: CameraPosition(target: _driverPosition!, zoom: 15),
              myLocationEnabled: false,
              onMapCreated: (controller) {
                _mapController = controller;
                _setMapStyle();
              },
              markers: {
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _driverPosition!,
                  icon: _carIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                ),
                if (_destination != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: _destination!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                  ),
              },
            ),

          if (_driverPosition != null)
            AnimatedBuilder(
              animation: _haloAnimation,
              builder: (context, child) => Positioned(
                top: MediaQuery.of(context).size.height / 2 - _haloAnimation.value / 2 - 80,
                left: MediaQuery.of(context).size.width / 2 - _haloAnimation.value / 2,
                child: Container(
                  width: _haloAnimation.value,
                  height: _haloAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withOpacity(0.3),
                  ),
                ),
              ),
            ),

          if (_showTripEndedMessage)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 800),
              child: Container(
                color: AppColors.black,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.emoji_events, color: AppColors.gold, size: 100),
                    SizedBox(height: 20),
                    Text(
                      "Bravo pour votre conduite !",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "On est arrivé à bon port grâce à vous !",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

          if (!_showTripEndedMessage)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "🚘 Trajet en cours",
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Suivez votre position en temps réel.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Distance restante : ${_remainingDistance.toStringAsFixed(1)} km",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      "Durée estimée : ${_estimatedDuration.toStringAsFixed(0)} min",
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

            if (!_showTripEndedMessage && _destination != null)
              Positioned(
                bottom: 140,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => openInNavigationApp(
                        _destination!.latitude,
                        _destination!.longitude,
                        useWaze: false,
                      ),
                      icon: const Icon(Icons.map, color: Colors.black),
                      label: const Text("Google Maps"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(140, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => openInNavigationApp(
                        _destination!.latitude,
                        _destination!.longitude,
                        useWaze: true,
                      ),
                      icon: const Icon(Icons.navigation, color: Colors.white),
                      label: const Text("Waze"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(120, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ],
                ),
              ),


          if (!_showTripEndedMessage)
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _endTrip,
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                icon: const Icon(Icons.check),
                label: const Text(
                  "Terminer la course",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> openInNavigationApp(double lat, double lng, {bool useWaze = false}) async {
  final String googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
  final String wazeUrl = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';

  final Uri uri = Uri.parse(useWaze ? wazeUrl : googleMapsUrl);

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  } else {
    throw 'Impossible d’ouvrir ${useWaze ? "Waze" : "Google Maps"}';
  }
}
