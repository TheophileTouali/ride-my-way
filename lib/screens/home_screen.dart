import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  int _currentPage = 0;
  String _hintFrom = "Détection en cours...";
  List<Map<String, dynamic>> _trips = [];

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('reservations')
        .where('userId', isEqualTo: user.uid)
        .get();

    final now = DateTime.now();

    final upcoming = snapshot.docs
        .where((doc) => (doc['timestamp'] as Timestamp).toDate().isAfter(now))
        .toList()
      ..sort((a, b) =>
          (a['timestamp'] as Timestamp).compareTo(b['timestamp'] as Timestamp));

    final past = snapshot.docs
        .where((doc) => (doc['timestamp'] as Timestamp).toDate().isBefore(now))
        .toList()
      ..sort((a, b) =>
          (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));

    setState(() {
      _trips = [
        if (upcoming.isNotEmpty)
          {
            "title": "Prochain trajet",
            "from": upcoming.first['from'],
            "to": upcoming.first['to'],
            "date": _formatDate(upcoming.first['timestamp']),
          },
        if (past.isNotEmpty)
          {
            "title": "Dernier trajet",
            "from": past.first['from'],
            "to": past.first['to'],
            "date": _formatDate(past.first['timestamp']),
          },
        {
          "title": "Voir tous mes trajets",
          "from": "",
          "to": "",
          "date": "",
        },
      ];
    });
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return "${date.day}/${date.month} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _detectCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS désactivé');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw Exception('Permission refusée');
      }
      if (permission == LocationPermission.deniedForever)
        throw Exception('Permission permanente refusée');

      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      final city = placemarks.first.locality ??
          placemarks.first.administrativeArea ??
          "Votre position";

      setState(() {
        _fromController.text = city;
        _hintFrom = city;
      });
    } catch (_) {
      setState(() {
        _hintFrom = "Saisir votre point de départ";
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final userName = userProvider.userName;
    final greeting = _getGreeting();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D0D0D), Color(0xFF1C1C1C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Accueil",
                          style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'PlayfairDisplay')),
                      IconButton(
                        icon: const Icon(Icons.person_outline,
                            color: AppColors.gold),
                        onPressed: () => context.go('/profile'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FadeInRight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                            ).createShader(bounds);
                          },
                          child: Text(
                            "$greeting $userName 👋",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'PlayfairDisplay',
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Préparez-vous à vivre un trajet d’exception. ✨",
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              fontFamily: 'PlayfairDisplay'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _fromController,
                    googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                    debounceTime: 800,
                    countries: ["fr"],
                    fetchCoordinates: true,
                    style: const TextStyle(color: Colors.white),
                    decoration:
                        _inputDecoration(_hintFrom, Icons.place_rounded),
                    onSuggestionClicked: (prediction) {
                      _fromController.text = prediction.description!;
                      FocusScope.of(context).unfocus();
                    },
                    overlayContainerBuilder: (child) => Material(
                      elevation: 2.0,
                      color: Colors.grey[900], // fond noir
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GooglePlacesAutoCompleteTextFormField(
                    textEditingController: _toController,
                    googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                    debounceTime: 800,
                    countries: ["fr"],
                    fetchCoordinates: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                        "Entrer une destination", Icons.search),
                    onSuggestionClicked: (prediction) {
                      _toController.text = prediction.description!;
                      FocusScope.of(context).unfocus();
                    },
                    onEditingComplete: () {
                      final from = _fromController.text.trim();
                      final to = _toController.text.trim();
                      if (to.isNotEmpty)
                        context.go('/results?from=$from&to=$to');
                    },
                    overlayContainerBuilder: (child) => Material(
                      elevation: 2.0,
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      child: child,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () {
                      final from = _fromController.text.trim();
                      final to = _toController.text.trim();
                      if (from.isNotEmpty && to.isNotEmpty) {
                        context.go('/results?from=$from&to=$to');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Merci de renseigner le départ et la destination"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          "Trouver un véhicule",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'PlayfairDisplay',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _homeButton(context, Icons.event_note, "Mes réservations",
                      '/reservations'),
                  _homeButton(context, Icons.favorite_border, "Mes favoris",
                      '/favorites'),
                  const SizedBox(height: 28),
                  if (_trips.isEmpty)
                    const Center(
                        child: CircularProgressIndicator(color: AppColors.gold))
                  else
                    Column(
                      children: [
                        SizedBox(
                          height: 160,
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) =>
                                setState(() => _currentPage = index),
                            itemCount: _trips.length,
                            itemBuilder: (context, index) {
                              final trip = _trips[index];
                              return _TripCard(
                                title: trip['title'],
                                from: trip['from'],
                                to: trip['to'],
                                date: trip['date'],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_trips.length,
                              (index) => _buildDot(index == _currentPage)),
                        ),
                      ],
                    ),
                  const SizedBox(height: 28),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Provider.of<UserProvider>(context, listen: false)
                            .logout();
                        context.go('/login');
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text("Se déconnecter"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
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

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
      filled: true,
      fillColor: Colors.grey[900],
      prefixIcon: Icon(icon, color: AppColors.gold),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade700),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.gold),
      ),
    );
  }

  Widget _homeButton(
      BuildContext context, IconData icon, String label, String route) {
    return InkWell(
      onTap: () => context.go(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: AppColors.gold.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'PlayfairDisplay'))),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 16 : 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.gold : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final String title;
  final String from;
  final String to;
  final String date;

  const _TripCard(
      {required this.title,
      required this.from,
      required this.to,
      required this.date});

  @override
  Widget build(BuildContext context) {
    final isRedirect = from.isEmpty && to.isEmpty;

    return FadeInUp(
      duration: const Duration(milliseconds: 400),
      child: Card(
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isRedirect
              ? Center(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/reservations'),
                    icon:
                        const Icon(Icons.directions_car, color: AppColors.gold),
                    label: const Text("Voir tous mes trajets",
                        style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'PlayfairDisplay')),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.gold),
                      foregroundColor: AppColors.gold,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'PlayfairDisplay')),
                    const SizedBox(height: 8),
                    Text("$from ➔ $to",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    Text("Départ prévu : $date",
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13)),
                  ],
                ),
        ),
      ),
    );
  }
}
