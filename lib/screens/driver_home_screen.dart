// lib/screens/driver_home_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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


class Trip {
  final String departure;
  final String destination;
  final DateTime date;
  final String status;
  final double price;

  Trip({
    required this.departure,
    required this.destination,
    required this.date,
    required this.status,
    required this.price,
  });
}

Future<List<Trip>> fetchDriverTrips() async {
  await Future.delayed(const Duration(milliseconds: 800));
  return [
    Trip(departure: "Paris", destination: "Versailles", date: DateTime.now().add(const Duration(days: 1)), status: 'à venir', price: 25.0),
    Trip(departure: "Paris", destination: "Lyon", date: DateTime.now().add(const Duration(days: 3)), status: 'à venir', price: 120.0),
    Trip(departure: "Orly", destination: "Paris", date: DateTime.now().subtract(const Duration(days: 1)), status: 'effectué', price: 35.0),
    Trip(departure: "Paris", destination: "Roissy Charles de Gaulle", date: DateTime.now().subtract(const Duration(days: 3)), status: 'effectué', price: 45.0),
    Trip(departure: "Paris", destination: "Disneyland", date: DateTime.now().subtract(const Duration(days: 6)), status: 'annulé', price: 60.0),
    Trip(departure: "La Défense", destination: "Paris", date: DateTime.now().subtract(const Duration(days: 2)), status: 'annulé', price: 18.0),
  ];
}


class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isVisible = false;

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
  }

  void _startAutoRefresh() {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        final newData = await _fetchNearbyPendingReservations();

        if (newData.isNotEmpty && newData.length != _nearbyReservations.length) {
          setState(() {
            _hasNewNearbyCourse = true;
            _nearbyReservations = newData;
          });

          // 🔊 Joue un son de notification
          _audioPlayer.play(AssetSource('sounds/notification.mp3')); // à mettre dans assets
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
                    Text(
                      "Bienvenue ${user?.firstName ?? 'conducteur'} 👋",
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: const [
                        Icon(Icons.star, color: Colors.amber, size: 20),
                        SizedBox(width: 4),
                        Text("4.8", style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                _buildWeatherCard(),
                const SizedBox(height: 24),
                _buildStatsSection(),
                const SizedBox(height: 24),
                _buildRevenueChart(),

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
                              onPressed: () => _acceptReservation(doc.id),
                              icon: const Icon(Icons.check_circle, color: AppColors.black),
                              label: const Text("Accepter cette course"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.black,
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
                      SizedBox(
                        height: 240,
                        child: FutureBuilder<List<Trip>>(
                          future: fetchDriverTrips(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator(color: AppColors.gold));
                            }
                            final trips = snapshot.data!;
                            return TabBarView(
                              children: ['à venir', 'effectué', 'annulé'].map((status) {
                                final filtered = trips.where((t) => t.status == status).toList();
                                if (filtered.isEmpty) {
                                  return Center(child: Text("Aucun trajet $status.", style: const TextStyle(color: Colors.white54)));
                                }
                                return ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _tripCard(filtered[i]),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

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
                      child: Column(
                        children: testimonials.map((t) => _testimonialCard(t)).toList(),
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
          future: fetchWeather(),
          builder: (context, snapshot) {
          if (!snapshot.hasData) {
              return _loadingCard("Chargement météo...");
          }
          final weather = snapshot.data!;
          return _infoCard(
              title: "Météo actuelle",
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // Bloc gauche (icône + ville + température)
                  Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                      children: [
                      const Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 38),
                      const SizedBox(height: 8),
                      const Text("Paris", style: TextStyle(color: Colors.white60, fontSize: 14)),
                      Text(
                          "${weather.temperature}°C",
                          style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                          ),
                      ),
                      ],
                  ),
                  ),

                  const SizedBox(width: 24),

                  // Bloc droit (détails)
                  Expanded(
                  child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Column(
                      children: [
                          _weatherDetailRow("Conditions", weather.condition),
                          const SizedBox(height: 6),
                          _weatherDetailRow("Vent", "${weather.windDirection} – ${weather.windSpeed} km/h"),
                          const SizedBox(height: 6),
                          _weatherDetailRow("Humidité", "${weather.humidity} %"),
                          const SizedBox(height: 6),
                          _weatherDetailRow("Ressenti", "${weather.feelsLike}°C"),
                      ],
                      ),
                  ),
                  ),
              ],
              ),
          );
          },
      );
      }

      Widget _weatherDetailRow(String label, String value) {
      return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
          Text(
              "$label :",
              style: const TextStyle(
              color: Colors.white60,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              ),
          ),
          Text(
              value,
              style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w600,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statRow("Trajets", "${stats.nbTrajets}"),
                _statRow("Kilomètres", "${stats.totalKm} km"),
                _statRow("Note moyenne", "${stats.note} ⭐"),
              ],
            ),
          );
        },
      );
    }

      Widget _tripCard(Trip trip) {
      return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade800),
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text("${trip.departure} ➜ ${trip.destination}", style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text("Date : ${trip.date.toLocal().toString().split(' ')[0]}", style: const TextStyle(color: Colors.white70)),
              Text("Tarif : ${trip.price.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white70)),
          ],
          ),
      );
      }

    Widget _buildRevenueChart() {
      return _infoCard(
        title: "Mes revenus (mois) 💸",
        child: SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final months = ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin'];
                      return Text(months[value.toInt() % 6], style: const TextStyle(color: Colors.white70, fontSize: 10));
                    },
                  ),
                ),
              ),
              barGroups: List.generate(6, (index) {
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: [320, 450, 270, 620, 500, 710][index].toDouble(),
                      width: 18,
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
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
  await Future.delayed(const Duration(milliseconds: 800));
  return DriverStats(nbTrajets: 14, totalKm: 320, note: 4.8);
}

class WeatherInfo {
  final int temperature;
  final String iconCode;

  final String condition;
  final String windDirection;
  final double windSpeed;
  final int humidity;
  final double feelsLike;

  WeatherInfo({
    required this.temperature,
    required this.iconCode,
    required this.condition,
    required this.windDirection,
    required this.windSpeed,
    required this.humidity,
    required this.feelsLike,
  });
}


Future<WeatherInfo> fetchWeather() async {
  await Future.delayed(const Duration(milliseconds: 500));
  return WeatherInfo(
    temperature: 26,
    iconCode: '01d',
    condition: 'Ensoleillé',
    windDirection: 'Nord-Ouest',
    windSpeed: 12.0,
    humidity: 60,
    feelsLike: 28.0,
  );
}

