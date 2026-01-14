import 'dart:convert';
import 'dart:ui' show FontFeature; // pour chiffres monospaces
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:characters/characters.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart'; // Doit contenir AppColors.gold
import 'package:cloud_functions/cloud_functions.dart';

// =========================
// Model & helpers
// =========================

String _formatPrice(double value) {
  // Format FR sans intl: "35,46 €"
  final s = value.toStringAsFixed(2).replaceAll('.', ',');
  return '$s €';
}

class RouteInfo {
  final double distanceKm;
  final int durationSeconds;

  const RouteInfo({
    required this.distanceKm,
    required this.durationSeconds,
  });
}

extension RouteInfoX on RouteInfo {
  Duration get duration => Duration(seconds: durationSeconds);

  String get durationLabel {
    final d = duration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);

    if (h <= 0) return "${m} min";
    return "${h}h ${m.toString().padLeft(2, '0')}";
  }
}

class VehicleOption {
  final String name;
  final IconData icon;
  final double base;
  final double perKm;
  final String badge; // ex: "Prestige", "Le + spacieux", "Le + éco"

  const VehicleOption(
    this.name,
    this.icon,
    this.base,
    this.perKm, {
    this.badge = '',
  });

  double price(double km) =>
      double.parse((base + perKm * km).toStringAsFixed(2));
}

// =========================
// Données
// =========================

const List<VehicleOption> _options = <VehicleOption>[
  VehicleOption(
    'Voitures électriques',
    Icons.electric_car,
    4.0,
    2.10, // 2,10 €/km
    badge: 'Silence d’or',
  ),
  VehicleOption(
    'Berlines',
    Icons.directions_car_filled,
    5.0,
    2.10, // 2,10 €/km
    badge: 'L’équilibre parfait',
  ),
  VehicleOption(
    'Vans Standing',
    Icons.airport_shuttle_rounded,
    6.5,
    3.70, // 3,70 €/km
    badge: 'Espace & prestance',
  ),
  VehicleOption(
    'Véhicules Premiums',
    Icons.directions_car,
    8.0,
    3.70, // 3,70 €/km
    badge: 'L’art du trajet',
  ),
  VehicleOption(
    'Motos',
    Icons.motorcycle,
    2.5,
    3.50, // 3,50 €/km
    badge: 'L’instinct libre',
  ),
];

// =========================
/* Écran principal */
// =========================

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
  String? durationLabel;

  @override
  void initState() {
    super.initState();
    _calculateDistance();
  }

  Future<void> _calculateDistance() async {
    setState(() => isLoading = true);

    try {
      final fromCoord = await getCoordinatesFromAddress(widget.from);
      final toCoord = await getCoordinatesFromAddress(widget.to);

      if (fromCoord == null || toCoord == null) {
        throw Exception("Coordonnées non trouvées");
      }

      final route = await getRouteInfoViaFunction(
        origin: fromCoord,
        destination: toCoord,
      );

      if (route == null) {
        throw Exception("Route non trouvée");
      }

      if (!mounted) return;

      setState(() {
        distanceKm = route.distanceKm;
        durationLabel = route.durationLabel;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Erreur distance: $e");

      if (!mounted) return;

      setState(() {
        distanceKm = null;
        durationLabel = null; // ✅ important
        isLoading = false;
      });
    }
  }

  String _bust(String? url) {
    if (url == null || url.isEmpty) return '';
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  Widget _buildHeader() {
    final user = context.watch<UserProvider>();
    final name = user.userName.trim();
    final hasName = name.isNotEmpty; // plus de check "Invité"

    final avatarUrl = _bust(user.avatarUrl);

    final title = hasName
        ? "Prêt à voyager avec distinction, $name ?"
        : "Prêt à voyager avec distinction ?";

    return FadeInDown(
      delay: const Duration(milliseconds: 80),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: AppColors.gold.withOpacity(0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasName)
                GoldAvatar(
                  name: name,
                  imageUrl: avatarUrl,
                  size: 28,
                )
              else
                const Icon(Icons.star_rounded, color: AppColors.gold, size: 22),

              const SizedBox(width: 10),

              // 🔥 Zone texte flexible sans overflow
              Expanded(
                child: GoldGradientText(
                  title,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'PlayfairDisplay',
                    letterSpacing: .2,
                    height: 1.25,
                    color: Colors.white,
                  ),
                  maxLines: 2, // ← limite à 2 lignes, pas de dépassement
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripCard() {
    final distLabel = (distanceKm != null)
        ? "${distanceKm!.toStringAsFixed(1)} km"
            "${(durationLabel != null ? " • $durationLabel" : "")}"
        : "-- km";

    return FadeInDown(
      child: Stack(
        children: [
          // Halo royal discret
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.9, -1.2),
                    radius: 1.2,
                    colors: [
                      AppColors.gold.withOpacity(0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Carte verre fumé
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.86),
              borderRadius: BorderRadius.circular(26),
              border:
                  Border.all(color: AppColors.gold.withOpacity(0.14), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  // faux inner shadow
                  color: Colors.black.withOpacity(0.20),
                  blurRadius: 10,
                  spreadRadius: -6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre + distance en pilule
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        border: Border.all(color: AppColors.gold, width: 1.2),
                      ),
                      child: const Icon(Icons.location_on_rounded,
                          color: AppColors.gold, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "Trajet",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontFamily: 'PlayfairDisplay',
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    DistancePill(distLabel),
                  ],
                ),
                const SizedBox(height: 14),
                // Origine / Destination
                RoutePointsLux(from: widget.from, to: widget.to),

                const SizedBox(height: 18),
                const ProgressStripeLux(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      // On évite l'overflow du skeleton en le rendant scrollable
      return const SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 20),
        child: GoldSkeleton(),
      );
    }

    if (distanceKm == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GoldGradientText(
              "Impossible de calculer le prix.",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _calculateDistance,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.gold.withOpacity(0.6)),
                foregroundColor: AppColors.gold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Réessayer"),
            ),
          ],
        ),
      );
    }

    final km = distanceKm!;
    final controller = ScrollController(); // Ajout du controller Scrollbar ✅

    return Scrollbar(
      controller: controller,
      thickness: 2,
      radius: const Radius.circular(12),
      thumbVisibility: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.8, -0.9),
                    radius: 1.2,
                    colors: [
                      AppColors.gold.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListView.separated(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: _options.length,
            separatorBuilder: (_, __) => const RoyalDivider(),
            itemBuilder: (context, index) {
              final opt = _options[index];
              return FadeInUp(
                delay: Duration(milliseconds: 70 * index),
                child: VehicleCard(
                  option: opt,
                  km: km,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.go(
                      '/confirmation',
                      extra: {
                        'from': widget.from,
                        'to': widget.to,
                        'vehicle': opt.name,
                        'price': opt.price(km),
                        'distance': km,
                      },
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.gold, size: 20),
          tooltip: 'Retour',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home'); // fallback
            }
          },
        ),
        title: const GoldGradientText(
          "Voyagez avec distinction",
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(10),
          child: RoyalDivider(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildTripCard(),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

// =========================
// Widgets premium réutilisables
// =========================

class RoyalDivider extends StatelessWidget {
  const RoyalDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            AppColors.gold.withOpacity(0.28),
            Colors.transparent
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class GoldGradientText extends StatelessWidget {
  final String text;
  final TextStyle style;

  // ✅ Ajout de paramètres facultatifs
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const GoldGradientText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final Shader linearGradient = const LinearGradient(
      colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0));

    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: style.copyWith(
        foreground: Paint()..shader = linearGradient,
      ),
    );
  }
}

class GoldAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const GoldAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 32,
  });

  String get _initials {
    final parts =
        name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return "•";
    if (parts.length == 1)
      return parts.first.characters.take(1).toString().toUpperCase();
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0x33FFD700), Color(0x338A6A00)],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0xFF151515),
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.gold,
          ),
        ),
      );
}

// Badge discret (outline fin, fond neutre, or atténué)
class PremiumBadge extends StatelessWidget {
  final String label;
  const PremiumBadge(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.45), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: .2,
          color: Color(0xCCFFD700), // or 80%
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// Prix dominant (gradient or plein, texte noir, glow, chiffres monospaces)
class PricePill extends StatelessWidget {
  final String value;
  const PricePill(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Color(0xFFFFE680), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          color: Colors.black,
          fontFamily: 'PlayfairDisplay',
          fontFeatures: [FontFeature.tabularFigures()],
          shadows: [
            Shadow(
                color: Colors.white24, blurRadius: 0.5, offset: Offset(0, 0)),
          ],
        ),
      ),
    );
  }
}

// Hover/Focus magnétique (Web/Desktop)
class HoverScale extends StatefulWidget {
  final Widget child;
  const HoverScale({super.key, required this.child});
  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.015 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class VehicleCard extends StatelessWidget {
  final VehicleOption option;
  final double km;
  final VoidCallback onTap;

  const VehicleCard({
    super.key,
    required this.option,
    required this.km,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = option.price(km);
    final isSmall = MediaQuery.of(context).size.width < 380;
    const double priceWidth = 116; // réserve pour la pastille prix

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HoverScale(
        child: Material(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icône
                  Hero(
                    tag: 'veh-${option.name}',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold, width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withOpacity(0.15),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(option.icon, color: AppColors.gold, size: 22),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Zone texte (titre + badge + sous-titre)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Wrap = le badge peut passer à la ligne pour ne pas couper le titre
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 10),
                              child: Text(
                                option.name,
                                maxLines:
                                    isSmall ? 2 : 1, // 2 lignes sur mobile
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  fontFamily: 'PlayfairDisplay',
                                ),
                              ),
                            ),
                            if (option.badge.isNotEmpty)
                              PremiumBadge(option.badge),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Confort ${option.name.toLowerCase()} • ~${km.toStringAsFixed(1)} km",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.2,
                            fontFamily: 'PlayfairDisplay',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Prix: largeur fixe pour ne pas écraser le titre
                  SizedBox(
                    width: priceWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PricePill(_formatPrice(price)),
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

// =========================
// Skeleton premium
// =========================

class GoldSkeleton extends StatelessWidget {
  const GoldSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (i) => _skeletonItem()).toList(),
    );
  }

  Widget _skeletonItem() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 78,
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment(-1, -0.2),
            end: Alignment(1, 0.2),
            colors: [Color(0xFF1A1A1A), Color(0xFF222222), Color(0xFF1A1A1A)],
            stops: [0.25, 0.5, 0.75],
          ),
          border: Border.all(color: AppColors.gold.withOpacity(0.08)),
          boxShadow: [
            BoxShadow(
                color: AppColors.gold.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 6))
          ],
        ),
      );
}

// =========================
// Geocoding utils
// =========================

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

Future<LatLng?> getCoordinatesFromAddress(String address) async {
  // IMPORTANT: Pour la prod, protégez cette clé (proxy Cloud Function) + restrictions GCP.
  const apiKey = "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI";

  final url = Uri.parse(
    "https://maps.googleapis.com/maps/api/geocode/json"
    "?address=${Uri.encodeComponent(address)}&key=$apiKey",
  );

  final response = await http.get(url);
  final data = json.decode(response.body);

  if (data['status'] == 'OK') {
    final location = data['results'][0]['geometry']['location'];
    return LatLng(location['lat'], location['lng']);
  }
  return null;
}

Future<RouteInfo?> getRouteInfoViaFunction({
  required LatLng origin,
  required LatLng destination,
}) async {
  try {
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final callable = functions.httpsCallable('getRouteInfo');

    final res = await callable.call({
      'origin': {'lat': origin.lat, 'lng': origin.lng},
      'destination': {'lat': destination.lat, 'lng': destination.lng},
    });

    final data = Map<String, dynamic>.from(res.data);

    return RouteInfo(
      distanceKm: (data['distanceKm'] as num).toDouble(),
      durationSeconds: (data['durationSeconds'] as num).toInt(),
    );
  } catch (e) {
    debugPrint("getRouteInfo function error: $e");
    return null;
  }
}

class DistancePill extends StatelessWidget {
  final String text;
  const DistancePill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          color: AppColors.gold,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }
}

class RoutePointsLux extends StatelessWidget {
  final String from;
  final String to;
  const RoutePointsLux({super.key, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Colonne timeline (pastilles + trait vertical dégradé)
        Column(
          children: [
            _GoldDot(),
            Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                ),
              ),
            ),
            _GoldDot(),
          ],
        ),
        const SizedBox(width: 10),
        // Textes
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PointLine(
                label: 'Départ',
                value: from,
              ),
              const SizedBox(height: 6),
              _PointLine(
                label: 'Arrivée',
                value: to,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoldDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.35),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
        border: Border.all(color: const Color(0xFFFFEAB0), width: 1),
      ),
    );
  }
}

class _PointLine extends StatelessWidget {
  final String label;
  final String value;
  const _PointLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // petit label or atténué
        Text(
          label,
          style: TextStyle(
            color: AppColors.gold.withOpacity(0.85),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 2),
        // adresse
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.2,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
      ],
    );
  }
}

class ProgressStripeLux extends StatefulWidget {
  const ProgressStripeLux({super.key});
  @override
  State<ProgressStripeLux> createState() => _ProgressStripeLuxState();
}

class _ProgressStripeLuxState extends State<ProgressStripeLux>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final sweep = _c.value; // 0..1
        return Stack(
          children: [
            // base
            Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5A4A0A), Color(0xFF8C6D14)],
                ),
              ),
            ),
            // lueur animée
            Positioned.fill(
              child: FractionallySizedBox(
                widthFactor: 0.28,
                alignment: Alignment(-1.0 + 2 * sweep, 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0x00FFE38A),
                        Color(0xFFFFD700),
                        Color(0x00FFE38A),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.35),
                        blurRadius: 14,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =========================
// Ligne or animée
// =========================

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
