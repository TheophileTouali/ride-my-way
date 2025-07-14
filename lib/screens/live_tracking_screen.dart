import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../themes/app_theme.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

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

      // Exemple : si on veut réagir à un changement de statut global
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
    _positionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen((position) {
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
        _estimatedDuration = (_remainingDistance / 0.5) * 1.2; // ≈30km/h
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
      await FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .update({
        'status': 'Terminée',
        'endTime': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // 🔁 Redirection conducteur vers feedback
        context.go('/feedback-driver/${widget.reservationId}');
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
              initialCameraPosition:
                  CameraPosition(target: _driverPosition!, zoom: 15),
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
