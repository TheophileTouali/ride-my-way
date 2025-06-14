import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';

import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  int _currentPage = 0;
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  String _hintFrom = "Détection en cours...";

  @override
  void initState() {
    super.initState();
    _detectCurrentLocation();
  }

  Future<void> _detectCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS désactivé');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Permission refusée');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Permission permanente refusée');

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      final city = placemarks.first.locality ?? placemarks.first.administrativeArea ?? "Votre position";

      setState(() {
        _fromController.text = city;
        _hintFrom = city;
      });
    } catch (e) {
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
    final userName = Provider.of<UserProvider>(context).userName;
    final greeting = _getGreeting();

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(backgroundColor: AppColors.black, elevation: 0, toolbarHeight: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Accueil", style: TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay')),
                IconButton(icon: const Icon(Icons.person_outline, color: AppColors.gold), onPressed: () => context.go('/profile')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Text("$greeting 👋", style: const TextStyle(color: AppColors.gold, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'PlayfairDisplay')),
                const SizedBox(width: 8),
                Flexible(child: Text(userName, style: const TextStyle(color: AppColors.gold, fontSize: 16, overflow: TextOverflow.ellipsis))),
              ]),
              const SizedBox(height: 28),

              // 🔸 CHAMP DEPART (avec autocomplétion)
              GooglePlacesAutoCompleteTextFormField(
                textEditingController: _fromController,
                googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                debounceTime: 800,
                countries: ["fr"],
                fetchCoordinates: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(_hintFrom, Icons.place_rounded),
                onSuggestionClicked: (prediction) {
                  _fromController.text = prediction.description!;
                  FocusScope.of(context).unfocus();
                },
                onPlaceDetailsWithCoordinatesReceived: (place) {
                  print("📍 Départ : \${place.description} (\${place.lat}, \${place.lng})");
                },
              ),
              const SizedBox(height: 16),

              // 🔸 CHAMP DESTINATION (avec autocomplétion)
              GooglePlacesAutoCompleteTextFormField(
                textEditingController: _toController,
                googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                debounceTime: 800,
                countries: ["fr"],
                fetchCoordinates: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration("Entrer une destination", Icons.search),
                onSuggestionClicked: (prediction) {
                  _toController.text = prediction.description!;
                  FocusScope.of(context).unfocus();
                },
                onPlaceDetailsWithCoordinatesReceived: (place) {
                  print("📍 Destination : \${place.description} (\${place.lat}, \${place.lng})");
                },
                onEditingComplete: () {
                  final from = _fromController.text.trim();
                  final to = _toController.text.trim();
                  if (to.isNotEmpty) context.go('/results?from=\$from&to=\$to');
                },
              ),

              const SizedBox(height: 24),
              _homeButton(context, Icons.event_note, "Mes réservations", '/reservations'),
              _homeButton(context, Icons.favorite_border, "Mes favoris", '/favorites'),

              const SizedBox(height: 28),
              SizedBox(
                height: 160,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: const [
                    _TripCard(title: "Prochain trajet", from: "Boissy st leger", to: "Paris", date: "24 mai à 19h30"),
                    _TripCard(title: "Dernier trajet", from: "Paris", to: "Créteil", date: "20 mai à 18h00"),
                    _TripCard(title: "Voir tous mes trajets", from: "", to: "", date: ""),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) => _buildDot(index == _currentPage)),
              ),
              const SizedBox(height: 28),

              Center(
                child: TextButton(
                  onPressed: () {
                    Provider.of<UserProvider>(context, listen: false).logout();
                    context.go('/login');
                  },
                  child: const Text("Se déconnecter", style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70),
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

  Widget _homeButton(BuildContext context, IconData icon, String label, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white))),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
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

  const _TripCard({required this.title, required this.from, required this.to, required this.date});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (from.isNotEmpty && to.isNotEmpty)
              Text("\$from ➔ \$to", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            if (date.isNotEmpty)
              Text("Départ prévu : \$date", style: const TextStyle(color: Colors.white60, fontSize: 13)),
            if (from.isEmpty && to.isEmpty)
              Center(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.gold),
                    foregroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text("Voir tous mes trajets"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
