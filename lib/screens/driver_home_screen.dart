// lib/screens/driver_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../themes/app_theme.dart';
import '../providers/driver_provider.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:animate_do/animate_do.dart'; // pour animation du bouton
import 'package:assets_audio_player/assets_audio_player.dart';
import '../models/trip.dart';
import 'package:lucide_icons/lucide_icons.dart'; 
import 'package:ride_my_way/services/weather_service.dart';




Future<({double lat, double lng})?> getCoordinatesFromAddress(String address) async {
  const apiKey = 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI'; // remplace par ta vraie clé
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
        return (lat: location['lat'] as double, lng: location['lng'] as double);
      } else {
        print("⚠️ Geocoding API status: ${data['status']}");
      }
    } else {
      print("❌ HTTP error: ${response.statusCode}");
    }
  } catch (e) {
    print("❌ Exception Geocoding: $e");
  }

  return null;
}

Future<WeatherInfo> getWeatherFromPosition() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
      throw Exception("La permission de localisation est requise.");
    }
  }

  final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  return await fetchWeather(position.latitude, position.longitude);
}




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
        .where('status', isEqualTo: 'Terminée') // uniquement les trajets terminés
        .get();

    Map<int, double> revenues = {}; // clé = numéro du mois, valeur = total €

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      final timestamp = data['timestamp'] as Timestamp?;
      if (timestamp == null) continue;

      final date = timestamp.toDate();
      final month = date.month; // 1 = Janvier, 2 = Février, etc.

      revenues[month] = (revenues[month] ?? 0) + price;
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

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isVisible = false;
  double _driverRating = 0.0;
  List<Map<String, dynamic>> _feedbacks = [];


  late Timer _refreshTimer;
  List<DocumentSnapshot> _nearbyReservations = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _hasNewNearbyCourse = false;
  final assetsAudioPlayer = AssetsAudioPlayer(); 


  @override
  void initState() {
    super.initState();
    _loadVisibility();
    _startAutoRefresh();
    _loadDriverStats(); // ⬅️ ajoute ceci
    _loadRecentFeedbacks(); 
  }

   Future<void> _loadRecentFeedbacks() async {
    final feedbacks = await fetchRecentFeedbacks();
    setState(() {
      _feedbacks = feedbacks;
    });
  }

  Future<void> _loadDriverStats() async {
  final stats = await fetchDriverStats();
  setState(() {
    _driverRating = stats.note;
  });
}

  void _startAutoRefresh() {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        final newData = await _fetchNearbyPendingReservations();

        if (newData.isNotEmpty && newData.length != _nearbyReservations.length) {
          setState(() {
            _hasNewNearbyCourse = true;
            _nearbyReservations = newData;
          });

          // 🔊 ✅ SON D’URGENCE
          AssetsAudioPlayer.newPlayer().open(
            Audio("assets/sounds/urgent_alert.mp3"),
            showNotification: false,
          );
        } else {
          setState(() {
            _hasNewNearbyCourse = false;
            _nearbyReservations = newData;
          });
        }
      });
    }


  


  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

    Future<List<Map<String, dynamic>>> fetchRecentFeedbacks() async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      print("📥 UID actuel : $uid");

      if (uid == null) {
        print("⚠️ Utilisateur non connecté, retour liste vide");
        return [];
      }

      try {
        print("🔎 Récupération des feedbacks (driverId = $uid)...");
        final snapshot = await FirebaseFirestore.instance
            .collection('feedbacks')
            .where('driverId', isEqualTo: uid)
            .get();

        print("✅ Avis récupérés : ${snapshot.docs.length}");

        final feedbacks = snapshot.docs
            .map((doc) => doc.data())
            .where((data) => data['fromDriver'] == false)
            .toList();

        print("🎯 Avis filtrés (from passager) : ${feedbacks.length}");

        // Tri par date décroissante
        feedbacks.sort((a, b) =>
            (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

        final limited = feedbacks.take(5).toList();

        for (final fb in limited) {
          print("📄 Avis retenu : ${fb['comment']} | Note : ${fb['rating']}");
        }

        return limited;
      } catch (e) {
        print("❌ Erreur lors de la récupération des feedbacks : $e");
        return [];
      }
    }






  Future<void> _loadVisibility() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
    if (doc.exists && doc.data()!.containsKey('isVisible')) {
      setState(() {
        _isVisible = doc['isVisible'];
      });
    }
  }

            Widget _buildNearbyButton() {
            return ElevatedButton.icon(
              onPressed: () {
                showNearbyCoursesDialog(context);
              },
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
        final player = AudioPlayer();
        final alertedTripIds = <String>{};
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.6), // Fonce le fond
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.grey.shade900,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 600),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titre + bouton fermer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Courses proches à accepter 🛰️",
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Contenu dynamique via FutureBuilder
                  FutureBuilder<List<DocumentSnapshot>>(
                  future: _fetchNearbyPendingReservations(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                            child: CircularProgressIndicator(color: AppColors.gold));
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
          final from = doc['from'] ?? '';
          final to = doc['to'] ?? '';
          final price = (doc['price'] as num?)?.toStringAsFixed(2) ?? 'N/A';
          final date = (doc['timestamp'] as Timestamp).toDate();
          final distance = (doc['distance'] as double?)?.toStringAsFixed(1) ?? '?';
          final duration = date.difference(DateTime.now());
          final timeUntil = duration.inMinutes < 60
              ? 'dans ${duration.inMinutes} min'
              : 'dans ${duration.inHours}h';

          final isUrgent = duration.inMinutes <= 5;

                return FadeInUp(
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on, color: AppColors.gold, size: 18),
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
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
                        const SizedBox(height: 6),
                        Text("Départ : ${date.toLocal().toString().split('.')[0]} ($timeUntil)",
                            style: const TextStyle(color: Colors.white70)),
                        Text("Distance : $distance km", style: const TextStyle(color: Colors.white70)),
                        Text("Prix : $price €", style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.gold)),
                            );

                            // 🔐 Sécurité : timeout au cas où ça bloque
                            await _acceptReservation(doc.id).timeout(
                              const Duration(seconds: 5),
                              onTimeout: () {
                                throw Exception("⏳ Timeout lors de l'acceptation de la course");
                              },
                            );

                            if (context.mounted) Navigator.of(context).pop(); // ferme loader
                            if (context.mounted) Navigator.of(context).pop(); // ferme popup
                            AssetsAudioPlayer.newPlayer().open(
                              Audio("assets/sounds/success.mp3"),
                              showNotification: false,
                            );


                            setState(() {
                              _hasNewNearbyCourse = false;
                              _nearbyReservations.removeWhere((r) => r.id == doc.id);
                            });

                            if (context.mounted) {
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (context) => Center(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: FadeIn( // 👈 Animation changée ici
                                      duration: const Duration(milliseconds: 500),
                                      child: Container(
                                        padding: const EdgeInsets.all(24),
                                        margin: const EdgeInsets.symmetric(horizontal: 24),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade900,
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.gold),
                                            const SizedBox(height: 16),
                                            const Text(
                                              "Course acceptée avec succès 🎉",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.gold,
                                                fontFamily: 'PlayfairDisplay',
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              "Vous pouvez maintenant consulter les détails dans vos trajets.",
                                              style: TextStyle(color: Colors.white70),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 24),
                                            ElevatedButton.icon(
                                              onPressed: () => Navigator.of(context).pop(),
                                              icon: const Icon(Icons.check, color: Colors.black),
                                              label: const Text("Fermer", style: TextStyle(color: Colors.black)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.gold,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );

                            }
                          } catch (e) {
                            if (context.mounted) Navigator.of(context).pop(); // ferme loader
                            print("❌ ERREUR acceptReservation : $e");
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                barrierDismissible: true,
                                builder: (context) => Center(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: FadeIn(
                                      duration: const Duration(milliseconds: 400),
                                      child: Container(
                                        padding: const EdgeInsets.all(24),
                                        margin: const EdgeInsets.symmetric(horizontal: 24),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade900,
                                          borderRadius: BorderRadius.circular(24),
                                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
                                            const SizedBox(height: 16),
                                            const Text(
                                              "Erreur lors de l'acceptation ❌",
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.redAccent,
                                                fontFamily: 'PlayfairDisplay',
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              "Une erreur est survenue. Veuillez réessayer ou vérifier votre connexion.",
                                              style: TextStyle(color: Colors.white70),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 24),
                                            ElevatedButton.icon(
                                              onPressed: () => Navigator.of(context).pop(),
                                              icon: const Icon(Icons.close, color: Colors.black),
                                              label: const Text("Fermer", style: TextStyle(color: Colors.black)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.redAccent,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );

                            }
                          }
                        },

                        icon: const Icon(Icons.check_circle_outline, color: Colors.black),
                        label: const Text("Accepter cette course", style: TextStyle(color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600),
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
      List<DocumentSnapshot> nearby = [];

      try {
        final currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        print('📍 Position actuelle du conducteur : Latitude: ${currentPosition.latitude}, Longitude: ${currentPosition.longitude}');

        final querySnapshot = await FirebaseFirestore.instance
            .collection('reservations')
            .where('status', isEqualTo: 'En attente')
            .get();

        for (var doc in querySnapshot.docs) {
          final from = doc['from'];
          if (from == null || from == '') continue;

          try {
            final coords = await getCoordinatesFromAddress(from);
            if (coords != null) {
              final distance = Geolocator.distanceBetween(
                currentPosition.latitude,
                currentPosition.longitude,
                coords.lat,
                coords.lng,
              ) / 1000;

              print("📦 Adresse: $from → Distance: ${distance.toStringAsFixed(1)} km");

              if (distance <= 15.0) {
                nearby.add(doc);
              }
            } else {
              print("⛔ Adresse ignorée (geocoding échoué) : $from");
            }
          } catch (e) {
            print("❌ Erreur de géocodage pour $from : $e");
          }
        }
      } catch (e) {
        print("❌ Erreur de géolocalisation : $e");
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

      final reservationRef = FirebaseFirestore.instance.collection('reservations').doc(docId);

      await reservationRef.update({
        'status': 'Confirmée',
        'driverId': uid,
        'driverName': driverName,
        'vehicle': vehicle,
      });

      print("✅ Course $docId acceptée par $driverName ($uid)");
    }




  Future<void> _toggleVisibility(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
      'isVisible': value,
    });
    setState(() {
      _isVisible = value;
    });
  }

  Future<List<Trip>> fetchDriverTrips() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('reservations')
          .where('driverId', isEqualTo: uid)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Trip(
          id: doc.id,
          from: data['from'] ?? '',
          to: data['to'] ?? '',
          departureTime: (data['timestamp'] as Timestamp).toDate(), // ✅ ICI !
          price: (data['price'] as num).toDouble(),
          status: data['status'] ?? '',
        );
      }).toList();
    } catch (e) {
      print("❌ ERREUR fetchDriverTrips: $e");
      return [];
    }
  }




  @override
    Widget build(BuildContext context) {
      final user = Provider.of<DriverProvider>(context).user;

      return Scaffold(
        backgroundColor: AppColors.black,
        appBar: AppBar(
          backgroundColor: AppColors.black,
          elevation: 0,
          title: const Text(
            'Accueil Conducteur',
            style: TextStyle(
              color: AppColors.gold,
              fontFamily: 'PlayfairDisplay',
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Row(
              children: [
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
                  onPressed: () {
                    Provider.of<DriverProvider>(context, listen: false).logout();
                    context.go('/login-driver');
                  },
                ),
              ],
            ),
          ],
        ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                            fontWeight: FontWeight.w400,
                          ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                          const SizedBox(width: 4),
                          Text(
                            _driverRating.toStringAsFixed(1), // ✅ version dynamique
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),

                    ),
                  ],
                ),

              // METEO
                const SizedBox(height: 32),
                _buildWeatherCard(),

                // 🔥 Nouvelle section : Courses proches à accepter
                const SizedBox(height: 24),
                ...(_hasNewNearbyCourse
    ? [
        Pulse(
          infinite: true,
          child: _buildNearbyButton(),
        ),
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
                  final from = doc['from'] ?? '';
                  final to = doc['to'] ?? '';
                  final price = doc['price']?.toStringAsFixed(2) ?? 'N/A';
                  final distance = (doc['distance'] as double?)?.toStringAsFixed(1) ?? '?';
                  final date = (doc['timestamp'] as Timestamp).toDate();
                  final now = DateTime.now();
                  final diff = date.difference(now);
                  final timeBefore = diff.inMinutes < 60
                      ? "dans ${diff.inMinutes} min"
                      : "dans ${diff.inHours} h";

                  final isUrgent = diff.inMinutes <= 5; // ✅ ajoute cette ligne ici

                  return FadeInUp(
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121212),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.route, color: AppColors.gold, size: 18),
                              SizedBox(width: 6),
                              Text("Trajet", style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "$from ➜ $to",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.white54, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                "Départ : ${date.toLocal().toString().split('.')[0]} ($timeBefore)",
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.straighten, color: Colors.white54, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                "Distance : $distance km",
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.attach_money, color: Colors.white54, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                "Prix : $price €",
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Center(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                await _acceptReservation(doc.id);
                                // Ajoute ici ta logique après acceptation (fermeture, son, toast, etc.)
                              } catch (e) {
                                print("❌ Erreur acceptReservation : $e");
                              }
                            },
                            icon: const Icon(Icons.check_circle, color: Colors.black),
                            label: Text(
                              isUrgent ? "ACCEPTER IMMÉDIATEMENT" : "Accepter cette course",
                              style: const TextStyle(color: Colors.black),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isUrgent ? Colors.redAccent : AppColors.gold,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600),
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

            // 🔁 Trajets classés par statut


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

                      // ✅ Bloc responsive avec chargement Firestore
                      Container(
                        height: MediaQuery.of(context).size.height * 0.45,
                        child: FutureBuilder<List<Trip>>(
                          future: fetchDriverTrips(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(color: AppColors.gold),
                              );
                            }

                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Center(
                                child: Text(
                                  "Aucun trajet trouvé.",
                                  style: TextStyle(color: Colors.white54),
                                ),
                              );
                            }

                            final trips = snapshot.data!;
                            final now = DateTime.now();

                            final Map<String, List<Trip>> categorizedTrips = {
                              'À venir': trips
                              .where((t) => t.status == 'Confirmée' && t.departureTime.isAfter(now))
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
                                    child: Text(
                                      "Aucun trajet $status.",
                                      style: const TextStyle(color: Colors.white54),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) => _tripCard(context, filtered[i]),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24), // ✅ Espace final
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildStatsSection(),
                const SizedBox(height: 24),
                _buildRevenueChart(),

                const SizedBox(height: 24),

                // 🔁 Avis passagers
                FutureBuilder<List<Testimonial>>(
                  future: fetchDriverTestimonials(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                    }
                    final testimonials = snapshot.data!;
                    return _infoCard(
                      title: "Avis récents 🗣️",
                      child:Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        ..._feedbacks.map((feedback) {
                          final comment = feedback['comment'] ?? 'Pas de commentaire';
                          final rating = (feedback['rating'] as num?)?.toDouble() ?? 0.0;
                          final date = (feedback['timestamp'] as Timestamp?)?.toDate();
                          final formattedDate = date != null
                              ? '${date.day}/${date.month}/${date.year}'
                              : '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.star, color: Colors.amber.shade400, size: 20),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      formattedDate,
                                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  comment,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),

                    );
                  },
                ),

                const SizedBox(height: 32),

                // 🔁 Voir profil
                ElevatedButton.icon(
                  onPressed: () => context.go('/driver-profile'),
                  icon: const Icon(Icons.person, color: AppColors.black),
                  label: const Text("Voir mon profil"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

      );
    }

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
                      radius: 24,
                      backgroundImage: NetworkImage(t.avatarUrl),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(
                          t.passengerName,
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                          ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                          children: List.generate(
                              5,
                              (i) => Icon(
                              i < t.rating.floor()
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 16,
                              color: Colors.amber,
                              ),
                          ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                          t.comment,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontStyle: FontStyle.italic,
                          ),
                          ),
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
                      Text(
                        weather.city,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
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

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
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
                      fontWeight: FontWeight.w500,
                    ),
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
                    _statColumn(Icons.directions_car, "${stats.nbTrajets}", "Trajets"),
                    _statColumn(Icons.map_rounded, "${stats.totalKm} km", "Kilomètres"),
                    _statColumn(Icons.star_rounded, "${stats.note.toStringAsFixed(1)}", "Note"),
                  ],
                ),
              );
            },
          );
        }

                  Widget _statColumn(IconData icon, String value, String label) {
            return Column(
              children: [
                Icon(icon, color: AppColors.gold, size: 30),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white54,
                  ),
                ),
              ],
            );
          }



    Widget _buildRevenueChart() {
    final months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin', 'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc'];

    return FutureBuilder<Map<int, double>>(
      future: fetchMonthlyRevenues(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _loadingCard("Chargement revenus...");

        final revenues = snapshot.data!;
        return _infoCard(
          title: "Mes revenus (mois) 💸",
          child: SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    getTooltipItem: (group, _, rod, __) {
                      return BarTooltipItem(
                        "${months[group.x]} : ${rod.toY.toInt()}€",
                        const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
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
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) => Text(
                        months[value.toInt()],
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barGroups: List.generate(12, (index) {
                  final revenue = revenues[index + 1] ?? 0.0; // Mois = index + 1
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
                          toY: 800,
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
            Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
    }

    Widget _loadingCard(String title) {
      return _infoCard(
        title: title,
        child: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    Widget _statRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[300])),
            Text(value, style: _valueTextStyle()),
          ],
        ),
      );
    }

    TextStyle _valueTextStyle() {
      return const TextStyle(
        color: AppColors.gold,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      );
    }
  }

// Mocked data classes and fetchers

class DriverStats {
  final int nbTrajets;
  final int totalKm;
  final double note;

  DriverStats({required this.nbTrajets, required this.totalKm, required this.note});
}

  Future<DriverStats> fetchDriverStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Utilisateur non connecté");

    // 1. Trajets terminés du conducteur
    final reservationsSnapshot = await FirebaseFirestore.instance
        .collection('reservations')
        .where('driverId', isEqualTo: uid)
        .where('status', whereIn: ['Confirmée', 'Terminée'])
        .get();

    final trajets = reservationsSnapshot.docs;
    int totalKm = 0;

    for (final doc in trajets) {
      final data = doc.data();
      totalKm += (data['distance'] as num?)?.round() ?? 0;
    }

    // 2. Feedbacks concernant ce conducteur
    final feedbacksSnapshot = await FirebaseFirestore.instance
        .collection('feedbacks')
        .where('driverId', isEqualTo: uid)
        .where('fromDriver', isEqualTo: false) // uniquement ceux venant de passagers
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




 
 Widget _tripCard(BuildContext context, Trip trip) {
  return GestureDetector(
    onTap: () {
      context.go('/driver/trip/${trip.id}');
    },
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
          // ... même contenu que tu avais ...
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.location_on, color: Color(0xFFFFD700), size: 20),
                  SizedBox(width: 6),
                  Text(
                    "Trajet",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, color: Colors.white60, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    trip.departureTime.toLocal().toIso8601String().split('T').first,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.euro, color: Colors.white60, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    trip.price.toStringAsFixed(2),
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                    children: [
                      TextSpan(
                        text: trip.from,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                      const TextSpan(
                        text: "  ➜  ",
                        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                      ),
                      TextSpan(
                        text: trip.to,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
