// VERSION OPTIMISÉE DE LiveTrackingPassengerScreen (confirmation avec son et animation ✅)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:audioplayers/audioplayers.dart';

class LiveTrackingPassengerScreen extends StatefulWidget {
  final String reservationId;
  const LiveTrackingPassengerScreen({super.key, required this.reservationId});

  @override
  State<LiveTrackingPassengerScreen> createState() => _LiveTrackingPassengerScreenState();
}

class _LiveTrackingPassengerScreenState extends State<LiveTrackingPassengerScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  LatLng? _destination;
  BitmapDescriptor? _carIcon;
  Timer? _refreshTimer;
  Timer? _reminderTimer;
  late AnimationController _haloController;
  late Animation<double> _haloAnimation;

  double _remainingDistance = 0;
  double _estimatedDuration = 0;
  String? _status;
  bool _hasConfirmedBoarding = false;
  bool _boardingDialogVisible = false;
  bool _showCheckmark = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};
  final PolylinePoints _polylinePoints = PolylinePoints();
  final String _googleApiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI';

  @override
  void initState() {
    super.initState();
    _loadCarIcon();
    _loadReservationData();
    _startDriverLocationUpdates();
    _listenReservationStatus();

    _haloController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _haloAnimation = Tween<double>(begin: 20, end: 40).animate(_haloController);
  }

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/car_gold.png',
    );
    setState(() {});
  }

  Future<void> _loadReservationData() async {
    final doc = await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .get();
    final data = doc.data();
    if (data != null) {
      final location = (data['status'] == 'En cours')
          ? data['dropoffLocation']
          : data['pickupLocation'];
      if (location != null) {
        setState(() => _destination = LatLng(location['lat'], location['lng']));
      }
    }
  }

  void _startDriverLocationUpdates() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final doc = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .get();
      final data = doc.data();
      if (data != null && data['driverLocation'] != null) {
        final loc = data['driverLocation'];
        final newPos = LatLng(loc['lat'], loc['lng']);
        setState(() => _driverPosition = newPos);
        _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
        _updateDistanceAndDuration();
        _getRoutePolyline();
      }
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
        _polylineCoordinates.clear();
        _polylineCoordinates.addAll(
            result.points.map((p) => LatLng(p.latitude, p.longitude)).toList());

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

  Future<void> _setMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_dark.json');
    _mapController?.setMapStyle(style);
  }

  void _listenReservationStatus() {
    FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data != null) {
        setState(() => _status = data['status']);

        if (_status == 'Terminée' && mounted) {
          context.go('/feedback/${widget.reservationId}');
        }

        if (_status == 'À bord') {
          _hasConfirmedBoarding = true;
          _reminderTimer?.cancel();
          _boardingDialogVisible = false;
        }

        if (_status == 'Arrivé' && !_hasConfirmedBoarding && !_boardingDialogVisible) {
          _boardingDialogVisible = true;
          _showBoardingDialog();
          _reminderTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
            if (_hasConfirmedBoarding || _status == 'En cours') {
              timer.cancel();
            } else {
              _showBoardingDialog();
            }
          });
        }

        _loadReservationData();
      }
    });
  }

  void _showBoardingDialog() {
    if (!_hasConfirmedBoarding && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Votre chauffeur est arrivé", style: TextStyle(color: AppColors.gold)),
          content: const Text(
            "Veuillez confirmer que vous êtes bien monté à bord. Le chauffeur pourra démarrer la course ensuite.",
            style: TextStyle(color: Colors.white70),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (!_hasConfirmedBoarding)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  elevation: 6,
                ),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await FirebaseFirestore.instance
                      .collection('reservations')
                      .doc(widget.reservationId)
                      .update({'status': 'À bord'});
                  setState(() {
                    _hasConfirmedBoarding = true;
                    _boardingDialogVisible = false;
                    _showCheckmark = true;
                  });
                  _reminderTimer?.cancel();
                  _audioPlayer.play(AssetSource('sounds/confirmed.mp3'));
                  Future.delayed(const Duration(seconds: 2), () {
                    setState(() => _showCheckmark = false);
                  });
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  "Je suis monté à bord",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'PlayfairDisplay',
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  String get statusMessage {
    switch (_status) {
      case 'En route':
        return "🚕 Votre chauffeur est en route vers vous";
      case 'Arrivé':
        return "📍 Votre chauffeur est arrivé à votre point de départ";
      case 'À bord':
        return "✅ Vous êtes monté à bord. Le chauffeur peut maintenant démarrer la course.";
      case 'En cours':
        return "🛣️ Trajet en cours vers votre destination";
      case 'Terminée':
        return "✅ Course terminée";
      default:
        return "⏳ En attente du chauffeur...";
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _reminderTimer?.cancel();
    _haloController.dispose();
    _audioPlayer.dispose();
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
              initialCameraPosition: CameraPosition(
                target: _driverPosition!,
                zoom: 15,
              ),
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

          if (_showCheckmark)
            Center(
              child: AnimatedOpacity(
                opacity: _showCheckmark ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: const Icon(Icons.check_circle, color: AppColors.gold, size: 90),
              ),
            ),

          Positioned(
            bottom: 20,
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
                  Text(
                    statusMessage,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
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
        ],
      ),
    );
  }
}
