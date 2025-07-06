import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';


class ResultsScreen extends StatefulWidget {
  final String from;
  final String to;

  const ResultsScreen({super.key, required this.from, required this.to});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  double? distanceKm;
  bool isLoading = true;
  String? selectedVehicle;

  final Map<String, Map<String, double>> vehiclePricing = {
    'Voitures électriques': {'base': 4.0, 'perKm': 1.2},
    'Berlines': {'base': 5.0, 'perKm': 1.5},
    'Vans Standing': {'base': 6.5, 'perKm': 2.0},
    'Classe S': {'base': 8.0, 'perKm': 2.8},
    'Classe E': {'base': 7.0, 'perKm': 2.2},
    'Motos': {'base': 2.5, 'perKm': 3.0},
  };

  @override
  void initState() {
    super.initState();
    _calculateDistance();
  }

  Future<void> _calculateDistance() async {
    try {
      final fromCoord = await getCoordinatesFromAddress(widget.from);
      final toCoord = await getCoordinatesFromAddress(widget.to);

      if (fromCoord == null || toCoord == null) {
        throw Exception("Coordonnées non trouvées");
      }

      final distanceInMeters = Geolocator.distanceBetween(
        fromCoord.lat, fromCoord.lng, toCoord.lat, toCoord.lng,
      );

      setState(() {
        distanceKm = double.parse((distanceInMeters / 1000).toStringAsFixed(2));
        isLoading = false;
      });
    } catch (e) {
      print("Erreur : $e");
      setState(() {
        distanceKm = null;
        isLoading = false;
      });
    }
  }

  double _calculatePrice(String type) {
    final base = vehiclePricing[type]!['base']!;
    final perKm = vehiclePricing[type]!['perKm']!;
    return double.parse((base + perKm * distanceKm!).toStringAsFixed(2));
  }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.gold, size: 20),
            tooltip: 'Retour',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home'); // fallback
              }
            },
              // Revenir à la page précédente
          ),
          title: const Text(
            "Voyagez avec distinction", // ou "Votre trajet sur mesure"
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              color: AppColors.gold,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ),



        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
              : distanceKm == null
                  ? const Center(
                      child: Text(
                        "Impossible de calculer le prix.",
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeInDown(
                          delay: const Duration(milliseconds: 100),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: AppColors.gold, size: 24),
                                const SizedBox(width: 8),
                                ShaderMask(
                                  shaderCallback: (Rect bounds) {
                                    return const LinearGradient(
                                      colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                                    ).createShader(bounds);
                                  },
                                  child: const Text(
                                    "Trouvez le véhicule parfait pour un trajet sans compromis",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'PlayfairDisplay',
                                      color: Colors.white, // masqué par le shader
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FadeInDown(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withOpacity(0.08),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              border: Border.all(color: AppColors.gold.withOpacity(0.15)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.location_on_rounded, color: AppColors.gold, size: 24),
                                        SizedBox(width: 10),
                                        Text(
                                          "Trajet",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontFamily: 'PlayfairDisplay',
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: distanceKm != null ? distanceKm!.toStringAsFixed(1) : "--",
                                            style: const TextStyle(
                                              color: AppColors.gold,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              fontFamily: 'PlayfairDisplay',
                                            ),
                                          ),
                                          const TextSpan(
                                            text: " km",
                                            style: TextStyle(
                                              color: AppColors.gold,
                                              fontSize: 16,
                                              fontStyle: FontStyle.italic,
                                              fontFamily: 'PlayfairDisplay',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text("De ${widget.from}", style: const TextStyle(color: Colors.white)),
                                Text("À ${widget.to}", style: const TextStyle(color: Colors.white)),
                                const SizedBox(height: 20),
                                const AnimatedGoldLine(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: vehiclePricing.keys.length,
                            itemBuilder: (context, index) {
                              final type = vehiclePricing.keys.elementAt(index);
                              final price = _calculatePrice(type);

                              final icon = {
                                'Voitures électriques': Icons.electric_car,
                                'Berlines': Icons.directions_car_filled,
                                'Vans Standing': Icons.airport_shuttle_rounded,
                                'Classe S': Icons.directions_car,
                                'Classe E': Icons.directions_car_outlined,
                                'Motos': Icons.motorcycle,
                              }[type];

                              return FadeInUp(
                                delay: Duration(milliseconds: 100 * index),
                                child: GestureDetector(
                                  onTap: () {
                                    context.go(
                                      '/confirmation',
                                      extra: {
                                        'from': widget.from,
                                        'to': widget.to,
                                        'vehicle': type,
                                        'price': price,
                                        'distance': distanceKm!,
                                      },
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[900],
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: AppColors.gold.withOpacity(0.15)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.gold.withOpacity(0.06),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        )
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.gold, width: 1.4),
                                          ),
                                          child: Icon(icon, color: AppColors.gold, size: 22),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                type,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontFamily: 'PlayfairDisplay',
                                                ),
                                              ),
                                              Text(
                                                "Confort ${type.toLowerCase()}",
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 14,
                                                  fontFamily: 'PlayfairDisplay',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          "$price €",
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.gold,
                                            fontFamily: 'PlayfairDisplay',
                                            shadows: [
                                              Shadow(
                                                color: Colors.black45,
                                                blurRadius: 2,
                                                offset: Offset(1, 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
        ),
      );
    }


}

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

Future<LatLng?> getCoordinatesFromAddress(String address) async {
  final apiKey = "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI";
  final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey");

  final response = await http.get(url);
  final data = json.decode(response.body);

  if (data['status'] == 'OK') {
    final location = data['results'][0]['geometry']['location'];
    return LatLng(location['lat'], location['lng']);
  }
  return null;
}

class AnimatedGoldLine extends StatefulWidget {
  const AnimatedGoldLine({super.key});

  @override
  State<AnimatedGoldLine> createState() => _AnimatedGoldLineState();
}

class _AnimatedGoldLineState extends State<AnimatedGoldLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeIn(
      duration: const Duration(milliseconds: 800),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 4,
              width: MediaQuery.of(context).size.width * _animation.value * 0.5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
