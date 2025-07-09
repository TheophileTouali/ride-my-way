import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../themes/app_theme.dart';

class DriverPickupTrackingScreen extends StatefulWidget {
  final String reservationId;

  const DriverPickupTrackingScreen({super.key, required this.reservationId});

  @override
  State<DriverPickupTrackingScreen> createState() => _DriverPickupTrackingScreenState();
}

class _DriverPickupTrackingScreenState extends State<DriverPickupTrackingScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  LatLng? _pickupLocation;
  BitmapDescriptor? _carIcon;
  StreamSubscription<Position>? _positionStream;
  final PolylinePoints _polylinePoints = PolylinePoints();
  List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};
  final String _googleApiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI';
  double _remainingDistance = 0;
  double _estimatedDuration = 0;
  late AnimationController _haloController;
  late Animation<double> _haloAnimation;

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
    _startLocationUpdates();
    _loadPickupData();

    _haloController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _haloAnimation = Tween<double>(begin: 20, end: 40).animate(_haloController);
  }

  Future<void> _loadPickupData() async {
    final doc = await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .get();
    final data = doc.data();
    if (data != null && data['pickupLocation'] != null) {
      final pickup = data['pickupLocation'];
      setState(() => _pickupLocation = LatLng(pickup['lat'], pickup['lng']));
      _getRoutePolyline();
    }
  }

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/car_gold.png',
    );
  }

  void _startLocationUpdates() {
    const settings = LocationSettings(accuracy: LocationAccuracy.high);
    _positionStream = Geolocator.getPositionStream(locationSettings: settings).listen((position) {
      final newPos = LatLng(position.latitude, position.longitude);
      setState(() => _driverPosition = newPos);

      FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .update({'driverLocation': {'lat': newPos.latitude, 'lng': newPos.longitude}});

      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
      _updateDistanceAndDuration();
      _getRoutePolyline();
    });
  }

  Future<void> _getRoutePolyline() async {
    if (_driverPosition == null || _pickupLocation == null) return;

    final result = await _polylinePoints.getRouteBetweenCoordinates(
      _googleApiKey,
      PointLatLng(_driverPosition!.latitude, _driverPosition!.longitude),
      PointLatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
    );

    if (result.points.isNotEmpty) {
      setState(() {
        _polylineCoordinates = result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
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

  void _updateDistanceAndDuration() {
    if (_driverPosition != null && _pickupLocation != null) {
      final meters = Geolocator.distanceBetween(
        _driverPosition!.latitude,
        _driverPosition!.longitude,
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
      );
      setState(() {
        _remainingDistance = meters / 1000;
        _estimatedDuration = (_remainingDistance / 0.5) * 1.2;
      });
    }
  }

  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_dark.json');
    _mapController?.setMapStyle(style);
  }

  Future<void> _confirmArrival() async {
    await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .update({'status': 'Arrivé'});

    if (mounted) context.go('/driver/trip/${widget.reservationId}');
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: const Text("Vers le passager"),
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
                  icon: _carIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                ),
                if (_pickupLocation != null)
                  Marker(
                    markerId: const MarkerId('pickup'),
                    position: _pickupLocation!,
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
                  const Text("🟡 Trajet vers le passager",
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      )),
                  const SizedBox(height: 4),
                  const Text("Restez sur le trajet jusqu'au point de départ.",
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text("Distance : ${_remainingDistance.toStringAsFixed(1)} km",
                      style: const TextStyle(color: Colors.white70)),
                  Text("Durée estimée : ${_estimatedDuration.toStringAsFixed(0)} min",
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              onPressed: _confirmArrival,
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.navigation),
              label: const Text(
                "Je suis arrivé",
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
