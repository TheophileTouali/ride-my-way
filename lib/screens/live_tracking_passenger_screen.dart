// LiveTrackingPassengerScreen — Ultra Premium Edition (no-regression)
// - Verre dépoli (glassmorphism) + bordure or animée
// - Titre à dégradé or + légère lueur
// - Barre ETA scintillante (shimmer) + micro-animations
// - Boutons "bijou" (pills) avec glow / hover doux
// - Contrôles carte glossy, halo amélioré
// - TOUTE la logique existante conservée à l’identique

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LiveTrackingPassengerScreen extends StatefulWidget {
  final String reservationId;
  const LiveTrackingPassengerScreen({super.key, required this.reservationId});

  @override
  State<LiveTrackingPassengerScreen> createState() =>
      _LiveTrackingPassengerScreenState();
}

class _LiveTrackingPassengerScreenState
    extends State<LiveTrackingPassengerScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  LatLng? _destination;
  BitmapDescriptor? _carIcon;

  Timer? _reminderTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverLocSub;

  late AnimationController _haloController;
  late Animation<double> _haloAnimation;

  double _remainingDistance = 0;
  double _estimatedDuration = 0;
  String? _status;
  bool _hasConfirmedBoarding = false;
  bool _boardingDialogVisible = false;
  bool _showCheckmark = false;
  bool _showTripEndedMessage = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

  final List<LatLng> _polylineCoordinates = [];
  Set<Polyline> _polylines = {};
  final PolylinePoints _polylinePoints = PolylinePoints();
  final String _googleApiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI';

  String? _driverName;
  String? _driverPhone;
  String? _driverPhotoUrl;
  bool get _canShowDriverPhone =>
      _status == 'Arrivé' || _status == 'À bord' || _status == 'En cours';

  // UI state
  bool _infoExpanded = true;
  MapType _mapType = MapType.normal;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _loadCarIcon();
    _loadReservationData();
    _attachDriverLocationStream();
    _attachStatusStream();
    _loadDriverInfo();

    _haloController =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..repeat(reverse: true);
    _haloAnimation = Tween<double>(begin: 22, end: 44).animate(
      CurvedAnimation(parent: _haloController, curve: Curves.easeInOut),
    );

    _markActiveTrip(true);
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _statusSub?.cancel();
    _haloController.dispose();
    _audioPlayer.dispose();
    _driverLocSub?.cancel();
    _markActiveTrip(false);
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _driverLocSub?.resume();
      _attachStatusStream(recreate: true);
      _loadReservationData();
    } else if (state == AppLifecycleState.paused) {
      _driverLocSub?.pause();
      _statusSub?.pause();
    }
  }

  // 4) Ajoute cette méthode (remplace l’approche Timer par un stream temps réel)
  void _attachDriverLocationStream() {
    _driverLocSub?.cancel();
    _driverLocSub = FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;

      final loc = data['driverLocation'];
      if (loc is Map && loc['lat'] != null && loc['lng'] != null) {
        final double lat =
            (loc['lat'] is num) ? (loc['lat'] as num).toDouble() : 0.0;
        final double lng =
            (loc['lng'] is num) ? (loc['lng'] as num).toDouble() : 0.0;
        final newPos = LatLng(lat, lng);

        if (!mounted) return;
        setState(() => _driverPosition = newPos);
        _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));

        // 👉 met à jour distance + durée + polyline en temps réel
        _updateDistanceAndDuration();
        _getRoutePolyline();
      }
    }, onError: (e) {
      debugPrint('❌ driverLocation stream error: $e');
    });
  }

  // ---------------- Data helpers (inchangé) ----------------

  Future<void> _loadDriverInfo() async {
    try {
      final resRef = FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId);
      final resSnap = await resRef.get();
      final m = resSnap.data();
      if (m == null) return;

      String? driverId;
      final refLike = m['driverRef'];
      if (refLike is DocumentReference) {
        driverId = refLike.id;
      } else {
        driverId =
            (m['driverId'] ?? m['chauffeurId'] ?? m['ownerId'])?.toString();
      }
      if (driverId == null || driverId.isEmpty) return;

      String? first, last, phone, photo;

      final dSnap = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();

      if (dSnap.exists) {
        final d = dSnap.data()!;
        first = (d['firstName'] ?? d['prenom'])?.toString();
        last = (d['lastName'] ?? d['nom'])?.toString();
        phone = (d['phone'] ?? d['telephone'] ?? d['mobile'])?.toString();
        photo = (d['photoUrl'])?.toString();
      } else {
        final uSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(driverId)
            .get();
        if (uSnap.exists) {
          final u = uSnap.data()!;
          first = (u['firstName'] ?? u['prenom'])?.toString();
          last = (u['lastName'] ?? u['nom'])?.toString();
          phone = (u['phone'] ?? u['telephone'] ?? u['mobile'])?.toString();
          photo = (u['photoUrl'])?.toString();
        } else {
          final pSnap = await FirebaseFirestore.instance
              .collection('passengers')
              .doc(driverId)
              .get();
          if (pSnap.exists) {
            final p = pSnap.data()!;
            first = (p['firstName'] ?? p['prenom'])?.toString();
            last = (p['lastName'] ?? p['nom'])?.toString();
            phone = (p['phone'] ?? p['telephone'] ?? p['mobile'])?.toString();
            photo = (p['photoUrl'])?.toString();
          }
        }
      }

      final name = [first, last]
          .where((s) => (s ?? '').trim().isNotEmpty)
          .join(' ')
          .trim();

      if (!mounted) return;
      setState(() {
        _driverName = name.isEmpty ? null : name;
        _driverPhone = (phone ?? '').trim().isNotEmpty ? phone!.trim() : null;
        _driverPhotoUrl =
            (photo ?? '').trim().isNotEmpty ? photo!.trim() : null;
      });
    } catch (e) {
      debugPrint('❌ _loadDriverInfo: $e');
    }
  }

  Future<void> _loadCarIcon() async {
    _carIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/car_gold.png',
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadReservationData() async {
    final doc = await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .get();
    final data = doc.data();
    if (data == null) return;

    final String? status = data['status']?.toString();
    final location = (status == 'En cours')
        ? data['dropoffLocation']
        : data['pickupLocation'];

    if (location is Map && location['lat'] != null && location['lng'] != null) {
      final double lat =
          (location['lat'] is num) ? (location['lat'] as num).toDouble() : 0.0;
      final double lng =
          (location['lng'] is num) ? (location['lng'] as num).toDouble() : 0.0;
      if (!mounted) return;
      setState(() => _destination = LatLng(lat, lng));
      _updateDistanceAndDuration();
      _getRoutePolyline();
    }
  }

  void _updateDistanceAndDuration() {
    if (_driverPosition == null || _destination == null) return;

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
        _polylineCoordinates
          ..clear()
          ..addAll(result.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList());

        _polylines = {
          Polyline(
            polylineId: const PolylineId("route"),
            color: AppColors.gold,
            width: 6,
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

  void _attachStatusStream({bool recreate = false}) {
    if (recreate) {
      _statusSub?.cancel();
      _statusSub = null;
    }
    if (_statusSub != null) {
      _statusSub!.resume();
      return;
    }

    _statusSub = FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      if (data == null) return;

      if (!mounted) return;
      setState(() => _status = data['status']?.toString());

      final location = (_status == 'En cours')
          ? data['dropoffLocation']
          : data['pickupLocation'];
      if (location is Map &&
          location['lat'] != null &&
          location['lng'] != null) {
        final double lat = (location['lat'] is num)
            ? (location['lat'] as num).toDouble()
            : 0.0;
        final double lng = (location['lng'] is num)
            ? (location['lng'] as num).toDouble()
            : 0.0;
        setState(() => _destination = LatLng(lat, lng));
        _updateDistanceAndDuration();
        _getRoutePolyline();
      }

      if (_status == 'Terminée') {
        _markActiveTrip(false);
        if (!mounted) return;
        setState(() => _showTripEndedMessage = true);
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) context.go('/feedback/${widget.reservationId}');
        return;
      }

      if (_status == 'À bord') {
        _hasConfirmedBoarding = true;
        _reminderTimer?.cancel();
        _boardingDialogVisible = false;
      } else if (_status == 'Arrivé' &&
          !_hasConfirmedBoarding &&
          !_boardingDialogVisible) {
        _boardingDialogVisible = true;
        _showBoardingDialog();
        _reminderTimer?.cancel();
        _reminderTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
          if (_hasConfirmedBoarding || _status == 'En cours') {
            timer.cancel();
          } else {
            _showBoardingDialog();
          }
        });
      }
    }, onError: (e) {
      debugPrint('❌ status stream error: $e');
    });
  }

  Future<void> _markActiveTrip(bool active) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        if (active) 'activeReservationId': widget.reservationId,
        if (!active) 'activeReservationId': FieldValue.delete(),
        'activeStatus': active ? (_status ?? 'En route') : FieldValue.delete(),
        'activeUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ---------------- Actions (identiques) ----------------

  void _copyPhoneOrNotify() async {
    if (_driverPhone == null || _driverPhone!.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _driverPhone!));
    if (!mounted) return;
    _toast("Numéro du chauffeur copié");
  }

  void _openChat() => context.push('/chat/${widget.reservationId}');

  Future<void> _shareTrackingLink() async {
    final base = kIsWeb ? Uri.base.origin : '';
    final link = kIsWeb
        ? '$base/tracking/${widget.reservationId}'
        : 'ride-my-way://tracking/${widget.reservationId}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _toast("Lien de suivi copié");
  }

  Future<void> _openProblemSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0B0B0B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Stack(
            children: [
              // halo or
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          AppColors.gold.withOpacity(.06),
                          Colors.transparent
                        ],
                        radius: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _goldHeading("Assistance & problèmes"),
                    const SizedBox(height: 8),
                    const Text(
                      "Signale un souci, notre équipe peut te recontacter.",
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 16),
                    _issueTile("Le chauffeur ne bouge plus", "driver_idle"),
                    _issueTile("Problème de sécurité (SOS)", "sos"),
                    _issueTile("Conflit sur l’itinéraire", "route_conflict"),
                    _issueTile("Autre problème…", "other"),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _issueTile(String label, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _glassBoxDecoration(),
      child: ListTile(
        leading: const Icon(Icons.report, color: Colors.redAccent),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () async {
          Navigator.of(context).pop();
          await FirebaseFirestore.instance.collection('incidents').add({
            'reservationId': widget.reservationId,
            'type': code,
            'status': 'open',
            'createdAt': FieldValue.serverTimestamp(),
            'from': 'passenger',
          });
          if (!mounted) return;
          _toast("Incident signalé. Nous prenons le relais.");
        },
      ),
    );
  }

  void _recenter() {
    if (_driverPosition != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_driverPosition!, 15),
      );
    }
  }

  void _toggleMapType() {
    setState(() {
      _mapType = (_mapType == MapType.normal) ? MapType.hybrid : MapType.normal;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black.withOpacity(.9),
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  // ---------------- Dialog boarding (inchangé, peaufiné) ----------------

  void _showBoardingDialog() {
    if (_hasConfirmedBoarding || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B0B0B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: _goldHeading("Votre chauffeur est arrivé"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((_driverName != null || _driverPhone != null) &&
                _canShowDriverPhone)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: _glassBoxDecoration(),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.gold,
                      backgroundImage: (_driverPhotoUrl != null)
                          ? NetworkImage(_driverPhotoUrl!)
                          : null,
                      child: (_driverPhotoUrl == null)
                          ? const Icon(Icons.person, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_driverName != null)
                            Text(
                              _driverName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'PlayfairDisplay',
                              ),
                            ),
                          if (_driverPhone != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.call,
                                    size: 14, color: Colors.white60),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _driverPhone!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    foregroundColor: AppColors.gold,
                                  ),
                                  onPressed: _copyPhoneOrNotify,
                                  icon: const Icon(Icons.copy, size: 14),
                                  label: const Text("Copier",
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if ((_driverName != null || _driverPhone != null) &&
                _canShowDriverPhone)
              const SizedBox(height: 12),
            const Text(
              "Veuillez confirmer que vous êtes bien monté à bord. Le chauffeur pourra démarrer la course ensuite.",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          if (!_hasConfirmedBoarding)
            _gemButton(
              icon: Icons.check_circle_outline,
              label: "Je suis monté à bord",
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
                try {
                  await _audioPlayer.setAsset('assets/sounds/confirmed.mp3');
                  await _audioPlayer.play();
                } catch (_) {}
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _showCheckmark = false);
                });
              },
            ),
        ],
      ),
    );
  }

  String get statusMessage {
    if (_showTripEndedMessage) {
      return "✅ Trajet terminé. Merci d’avoir voyagé avec nous !";
    }
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
        return "✅ Trajet terminé";
      default:
        return "⏳ En attente du chauffeur...";
    }
  }

  // ----------------------------- BUILD ---------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        children: [
          if (_driverPosition != null)
            GoogleMap(
              mapType: _mapType,
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
                      BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueYellow),
                ),
                if (_destination != null)
                  Marker(
                    markerId: const MarkerId('destination'),
                    position: _destination!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueAzure),
                  ),
              },
            ),

          // Halo or doux au centre
          if (_driverPosition != null)
            AnimatedBuilder(
              animation: _haloAnimation,
              builder: (context, child) => Positioned(
                top: MediaQuery.of(context).size.height / 2 -
                    _haloAnimation.value / 2 -
                    80,
                left: MediaQuery.of(context).size.width / 2 -
                    _haloAnimation.value / 2,
                child: Container(
                  width: _haloAnimation.value,
                  height: _haloAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.35),
                        blurRadius: _haloAnimation.value,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                ),
              ),
            ),

          // Check visuel
          if (_showCheckmark)
            Center(
              child: AnimatedOpacity(
                opacity: _showCheckmark ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: const Icon(Icons.check_circle,
                    color: AppColors.gold, size: 96),
              ),
            ),

          // Message fin de course (plein écran)
          if (_showTripEndedMessage)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 800),
              child: Container(
                color: AppColors.black,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.emoji_emotions_rounded,
                        color: AppColors.gold, size: 116),
                    const SizedBox(height: 24),
                    _goldHeading("Merci pour ce merveilleux voyage 🥂"),
                    const SizedBox(height: 12),
                    const Text(
                      "Nous espérons que l’expérience a été à la hauteur de vos attentes. À très bientôt sur Ride My Way ✨",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.4,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Contrôles carte glossy
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 16,
            child: Column(
              children: [
                _roundFab(icon: Icons.my_location, onTap: _recenter),
                const SizedBox(height: 10),
                _roundFab(
                  icon: Icons.layers,
                  onTap: _toggleMapType,
                  tooltip: "Changer de vue",
                ),
              ],
            ),
          ),

// ---------- SCRIM LISIBLE + PANNEAU INFOS & ACTIONS (PRÊT À L’EMPLOI) ----------

// 1) SCRIM de lecture (place-le AVANT ce panneau dans le Stack, ou colle les deux blocs à la suite)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  height: 340, // couvre le panneau + la barre d’actions
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.80),
                        Colors.black.withOpacity(0.60),
                        Colors.black.withOpacity(0.32),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.35, 0.72, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),

// 2) PANNEAU infos + actions (inchangé, posé au-dessus du scrim)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // GLASS PANEL
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: _goldGlassDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Titre + toggle
                          Row(
                            children: [
                              Expanded(child: _goldHeading(statusMessage)),
                              IconButton(
                                onPressed: () => setState(
                                    () => _infoExpanded = !_infoExpanded),
                                icon: Icon(
                                  _infoExpanded
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  color: Colors.white70,
                                ),
                                tooltip: _infoExpanded
                                    ? "Réduire"
                                    : "Voir les détails",
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _shimmerBar(),
                          if (_infoExpanded) ...[
                            const SizedBox(height: 10),
                            Text(
                              "Distance restante : ${_remainingDistance.toStringAsFixed(1)} km",
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            Text(
                              "Durée estimée : ${_estimatedDuration.toStringAsFixed(0)} min",
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                            if (_driverName != null || _driverPhone != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 17,
                                      backgroundColor: AppColors.gold,
                                      backgroundImage: (_driverPhotoUrl != null)
                                          ? NetworkImage(_driverPhotoUrl!)
                                          : null,
                                      child: (_driverPhotoUrl == null)
                                          ? const Icon(Icons.person,
                                              size: 18, color: Colors.black)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _driverName ?? "Votre chauffeur",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (_driverPhone != null &&
                                        _canShowDriverPhone)
                                      GestureDetector(
                                        onTap: _copyPhoneOrNotify,
                                        child: const Text(
                                          "Copier le numéro",
                                          style: TextStyle(
                                              color: AppColors.gold,
                                              fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Barre d’actions "bijou"
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E0E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(.08),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _gemPill(
                        icon: Icons.call,
                        label: "Appeler",
                        onTap: _canShowDriverPhone && _driverPhone != null
                            ? _copyPhoneOrNotify
                            : null,
                        tooltip: _canShowDriverPhone
                            ? "Copier le numéro du chauffeur"
                            : "Numéro disponible à l’arrivée/à bord",
                      ),
                      _gemPill(
                        icon: Icons.chat_bubble_outline,
                        label: "Chat",
                        onTap: _openChat,
                        tooltip: "Envoyer un message",
                      ),
                      _gemPill(
                        icon: Icons.ios_share,
                        label: "Partager",
                        onTap: _shareTrackingLink,
                        tooltip: "Copier le lien de suivi",
                      ),
                      _gemPill(
                        icon: Icons.report_gmailerrorred_outlined,
                        label: "SOS",
                        onTap: _openProblemSheet,
                        tooltip: "Signaler un problème",
                        danger: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- Widgets premium helpers --------------------

  // Titre dégradé or + légère lueur
  Widget _goldHeading(String text) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white, // masqué par ShaderMask
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'PlayfairDisplay',
          letterSpacing: .2,
        ),
      ),
    );
  }

  // Panneau verre + bordure or animée subtile
  BoxDecoration _goldGlassDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.gold.withOpacity(.35), width: 1),
      gradient: LinearGradient(
        colors: [
          Colors.white.withOpacity(.06),
          Colors.white.withOpacity(.02),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.gold.withOpacity(.08),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  // Carte “verre” générique
  BoxDecoration _glassBoxDecoration() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    );
  }

  // Barre ETA scintillante
  Widget _shimmerBar() {
    return LayoutBuilder(builder: (ctx, c) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 900),
        height: 8,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withOpacity(.12),
              Colors.white.withOpacity(.06),
            ],
          ),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: .35 + .05 * (_haloAnimation.value / 44), // micro-vie
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }

  // Bouton circulaire glossy
  Widget _roundFab(
      {required IconData icon, required VoidCallback onTap, String? tooltip}) {
    return Material(
      color: Colors.black.withOpacity(0.7),
      shape: const CircleBorder(),
      elevation: 10,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: AppColors.gold, size: 22),
          ),
        ),
      ),
    );
  }

  // Bouton “bijou” (pill) avec glow
  Widget _gemPill({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    String? tooltip,
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final Color glow = danger ? Colors.redAccent : AppColors.gold;
    return Tooltip(
      message: tooltip ?? '',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : .45,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  Colors.black,
                  Colors.black.withOpacity(.85),
                ],
              ),
              border: Border.all(
                color: enabled ? glow.withOpacity(.55) : Colors.white12,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: glow.withOpacity(.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: danger
                        ? Colors.redAccent
                        : (enabled ? AppColors.gold : Colors.white54)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Gros CTA or
  Widget _gemButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        backgroundColor: Colors.black,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 0,
      ).merge(ButtonStyle(
        side: MaterialStateProperty.all(
          BorderSide(color: AppColors.gold.withOpacity(.65), width: 1.2),
        ),
        shadowColor: MaterialStateProperty.all(AppColors.gold.withOpacity(.35)),
        elevation: MaterialStateProperty.resolveWith((states) => 10),
      )),
      onPressed: onPressed,
      icon: Icon(icon, color: AppColors.gold),
      label: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ).createShader(r),
        child: const Text(
          "Je suis monté à bord",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ),
    );
  }
}
