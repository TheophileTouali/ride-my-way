// lib/screens/edit_driver_profile_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'dart:ui'; // BackdropFilter/blur
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';

import '../providers/driver_provider.dart';
import '../models/driver_user.dart';
import '../themes/app_theme.dart';

/// ----------
///  LUX KIT — réutilisable (même look & feel que l’écran profil)
/// ----------
class Lux {
  static const gold = AppColors.gold; // #FFD700
  static const deepGold = AppColors.deepGold; // #A87C00
  static const ink = Color(0xFF0E0E10);

  static const gradientGold = LinearGradient(
    colors: [gold, deepGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Shader metallicGold(Rect rect) => const LinearGradient(
        colors: [
          Color(0xFFFFF3B0),
          Color(0xFFFFD700),
          Color(0xFFC9A300),
          Color(0xFFFFE38A),
          Color(0xFFA77A00),
        ],
        stops: [0.0, .25, .5, .75, 1],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

  static BoxDecoration frosted([double opacity = .50]) => BoxDecoration(
        color: Colors.black.withOpacity(opacity),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.45),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      );
}

class FrostedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final double blur;
  final double opacity;
  final BorderRadius radius;
  const FrostedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.blur = 18,
    this.opacity = .50,
    this.radius = const BorderRadius.all(Radius.circular(22)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: Lux.frosted(opacity),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(padding: padding, child: child),
        ),
      ),
    );
  }
}

void showLuxToast(
  BuildContext context, {
  required String message,
  IconData icon = Icons.verified_rounded,
  Duration duration = const Duration(milliseconds: 1400),
}) {
  final overlay = Overlay.of(context);
  if (overlay == null) return;

  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (_) => _LuxToast(
      message: message,
      icon: icon,
      onDone: () => entry.remove(),
      duration: duration,
    ),
  );

  overlay.insert(entry);
}

class _LuxToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final VoidCallback onDone;
  final Duration duration;

  const _LuxToast({
    required this.message,
    required this.icon,
    required this.onDone,
    required this.duration,
  });

  @override
  State<_LuxToast> createState() => _LuxToastState();
}

class _LuxToastState extends State<_LuxToast> {
  double _opacity = 0;
  double _y = -10;

  @override
  void initState() {
    super.initState();

    // apparition
    Future.delayed(const Duration(milliseconds: 10), () {
      if (!mounted) return;
      setState(() {
        _opacity = 1;
        _y = 0;
      });
    });

    // disparition
    Future.delayed(widget.duration, () {
      if (!mounted) return;
      setState(() {
        _opacity = 0;
        _y = -10;
      });

      Future.delayed(const Duration(milliseconds: 260), () {
        if (!mounted) return;
        widget.onDone();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 12;

    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: _opacity,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            offset: Offset(0, _y / 100),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withOpacity(.22)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(.18),
                        blurRadius: 26,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: Lux.gradientGold,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(.25),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: Colors.black, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ShaderMask(
                        shaderCallback: (r) => Lux.metallicGold(r),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MetallicTitle extends StatelessWidget {
  final String text;
  final double size;
  const MetallicTitle(this.text, {super.key, this.size = 20});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => Lux.metallicGold(rect),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: size,
          fontWeight: FontWeight.bold,
          color: Colors.white, // couvert par shader
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class GoldDivider extends StatelessWidget {
  final double height;
  const GoldDivider({super.key, this.height = 1});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x00FFD700), Color(0x66FFD700), Color(0x00FFD700)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }
}

class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool loading;
  const GoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.loading = false,
  });
  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: Lux.gradientGold,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Lux.gold.withOpacity(_hover ? .60 : .38),
            blurRadius: _hover ? 30 : 20,
            spreadRadius: _hover ? 1.5 : 0.8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.loading ? null : widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null && !widget.loading) ...[
                  Icon(widget.icon, color: Colors.black, size: 20),
                  const SizedBox(width: 10),
                ],
                if (widget.loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                else
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .2,
                      fontSize: 16,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Particules dorées très légères (perf-safe)
class GoldParticles extends StatefulWidget {
  final int count;
  const GoldParticles({super.key, this.count = 14});
  @override
  State<GoldParticles> createState() => _GoldParticlesState();
}

class _GoldParticlesState extends State<GoldParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => CustomPaint(
          painter: _GoldParticlesPainter(c.value, widget.count),
          size: Size.infinite),
    );
  }
}

class _GoldParticlesPainter extends CustomPainter {
  final double t;
  final int count;
  _GoldParticlesPainter(this.t, this.count);
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(21);
    for (var i = 0; i < count; i++) {
      final bx = rnd.nextDouble(), by = rnd.nextDouble(), phase = i / count;
      final x = (bx + t * (.07 + phase * .02)) % 1.0;
      final y = (by + sin(2 * pi * (t + phase)) * .002) % 1.0;
      final pos = Offset(x * size.width, y * size.height);
      final r = 1.0 + (i % 3) * .6;
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..color = Color.lerp(AppColors.deepGold.withOpacity(.35),
            AppColors.gold.withOpacity(.75), (i % 7) / 7)!;
      canvas.drawCircle(pos, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldParticlesPainter old) => old.t != t;
}

/// ----------
///  ECRAN — Edition du profil conducteur (Billionaire Edition)
/// ----------
class EditDriverProfileScreen extends StatefulWidget {
  const EditDriverProfileScreen({super.key});
  @override
  State<EditDriverProfileScreen> createState() =>
      _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends State<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _firstNameC;
  late final TextEditingController _lastNameC;
  late final TextEditingController _emailC; // lecture seule
  late final TextEditingController _phoneC;
  late final TextEditingController _addressC;
  late final TextEditingController _birthdateC;

  // Véhicule
  late final TextEditingController _vehicleBrandC;
  late final TextEditingController _vehicleModelC;
  late final TextEditingController _vehicleYearC;
  late final TextEditingController _licensePlateC;
  late final TextEditingController _driverLicenseNumberC;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<DriverProvider>(context, listen: false).user;

    _firstNameC = TextEditingController(text: user?.firstName ?? '');
    _lastNameC = TextEditingController(text: user?.lastName ?? '');
    _emailC = TextEditingController(text: user?.email ?? '');
    _phoneC = TextEditingController(text: user?.phone ?? '');
    _addressC = TextEditingController(text: user?.address ?? '');
    _birthdateC = TextEditingController(text: user?.birthdate ?? '');

    _vehicleBrandC = TextEditingController(text: user?.vehicleBrand ?? '');
    _vehicleModelC = TextEditingController(text: user?.vehicleModel ?? '');
    _vehicleYearC = TextEditingController(text: user?.vehicleYear ?? '');
    _licensePlateC = TextEditingController(text: user?.licensePlate ?? '');
    _driverLicenseNumberC =
        TextEditingController(text: user?.driverLicenseNumber ?? '');
  }

  @override
  void dispose() {
    _firstNameC.dispose();
    _lastNameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _addressC.dispose();
    _birthdateC.dispose();
    _vehicleBrandC.dispose();
    _vehicleModelC.dispose();
    _vehicleYearC.dispose();
    _licensePlateC.dispose();
    _driverLicenseNumberC.dispose();
    super.dispose();
  }

  // ---- Date de naissance
  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial =
        _parseDate(_birthdateC.text) ?? DateTime(now.year - 25, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year - 16, 12, 31),
      helpText: 'Sélectionner la date de naissance',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              surface: AppColors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black87,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _birthdateC.text = _formatDate(picked); // yyyy-MM-dd
      setState(() {});
    }
  }

  DateTime? _parseDate(String s) {
    try {
      if (s.trim().isEmpty) return null;
      return DateTime.parse(s.trim());
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  // ---- Décoration champs (premium)
  InputDecoration _luxDec(String label, {Widget? suffix, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle:
          const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Colors.white38),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.gold, width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
        borderRadius: BorderRadius.circular(14),
      ),
      filled: true,
      fillColor: Colors.black.withOpacity(0.40),
      suffixIcon: suffix,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: MetallicTitle(text, size: 18),
    );
  }

  // ---- Enregistrement (inchangé côté données)
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Session expirée. Merci de vous reconnecter.')),
      );
      context.go('/login-driver');
      return;
    }

    setState(() => _saving = true);

    try {
      final Map<String, dynamic> payload = {
        'firstName': _firstNameC.text.trim(),
        'lastName': _lastNameC.text.trim(),
        'phone': _phoneC.text.trim(),
        'address': _addressC.text.trim(),
        'birthdate': _birthdateC.text.trim(),
        'vehicleBrand': _vehicleBrandC.text.trim(),
        'vehicleModel': _vehicleModelC.text.trim(),
        'vehicleYear': _vehicleYearC.text.trim(),
        'licensePlate': _licensePlateC.text.trim().toUpperCase(),
        'driverLicenseNumber': _driverLicenseNumberC.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Nettoyage des vides si souhaité
      payload.removeWhere((k, v) => v is String && v.isEmpty);

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .set(payload, SetOptions(merge: true));

      // Rafraîchir le modèle local
      await Provider.of<DriverProvider>(context, listen: false)
          .initializeUser();

      if (mounted) {
        showLuxToast(
          context,
          message: 'Profil mis à jour avec succès',
          icon: Icons.verified_rounded,
        );

        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black87,
            content: Text('Erreur lors de l’enregistrement : $e',
                style: const TextStyle(color: Colors.redAccent)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DriverUser? user = Provider.of<DriverProvider>(context).user;

    if (user == null) {
      Future.microtask(() => context.go('/login-driver'));
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: Lux.ink,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: const MetallicTitle('Modifier mon profil', size: 20),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  )
                : const Text('Enregistrer',
                    style: TextStyle(
                        color: AppColors.gold, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
        ],
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(.22)),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fond premium + halo discret + particules
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0C0C0E), Color(0xFF09090B)],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: -80,
            width: 340,
            height: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.gold.withOpacity(.10), Colors.transparent],
                ),
              ),
            ),
          ),
          const Positioned.fill(
              child: IgnorePointer(child: GoldParticles(count: 14))),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Animate(
                        effects: [
                          FadeEffect(duration: 450.ms),
                          MoveEffect(
                              begin: const Offset(0, 14), duration: 450.ms),
                        ],
                        child: FrostedCard(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle('Identité'),
                              const GoldDivider(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _firstNameC,
                                      decoration: _luxDec('Prénom'),
                                      style:
                                          const TextStyle(color: Colors.white),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Prénom requis'
                                              : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _lastNameC,
                                      decoration: _luxDec('Nom'),
                                      style:
                                          const TextStyle(color: Colors.white),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Nom requis'
                                              : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailC,
                                readOnly: true,
                                decoration: _luxDec('Email').copyWith(
                                  helperText:
                                      'Modifiable depuis l’espace sécurité',
                                  helperStyle: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                ),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Animate(
                        effects: [
                          FadeEffect(duration: 480.ms),
                          MoveEffect(
                              begin: const Offset(0, 18), duration: 480.ms),
                        ],
                        child: FrostedCard(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle('Contact & Adresse'),
                              const GoldDivider(),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneC,
                                decoration: _luxDec('Téléphone',
                                    hint: 'Ex: +33 6 12 34 56 78'),
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: Colors.white),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Téléphone requis'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              GooglePlacesAutoCompleteTextFormField(
                                textEditingController: _addressC,
                                googleAPIKey:
                                    "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                                debounceTime: 800,
                                countries: const ["fr"],
                                fetchCoordinates: true,
                                style: const TextStyle(color: Colors.white),
                                decoration: _luxDec('Adresse'),
                                onSuggestionClicked: (prediction) {
                                  _addressC.text = prediction.description ?? '';
                                  FocusScope.of(context).unfocus();
                                  setState(
                                      () {}); // pour rafraîchir l’UI si besoin
                                },
                                onChanged: (value) => _addressC.text = value,
                                onPlaceDetailsWithCoordinatesReceived: (_) {},
                                validator: (_) =>
                                    null, // ✅ optionnel / non bloquant
                                overlayContainerBuilder: (child) => Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(.92),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: Colors.white.withOpacity(.10)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(.55),
                                          blurRadius: 22,
                                          offset: const Offset(0, 12),
                                        ),
                                      ],
                                    ),
                                    child: child,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _birthdateC,
                                readOnly: true,
                                decoration: _luxDec(
                                  'Date de naissance',
                                  suffix: IconButton(
                                    tooltip: 'Choisir une date',
                                    icon: const Icon(Icons.date_range,
                                        color: AppColors.gold),
                                    onPressed: _pickBirthdate,
                                  ),
                                ),
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Animate(
                        effects: [
                          FadeEffect(duration: 510.ms),
                          MoveEffect(
                              begin: const Offset(0, 22), duration: 510.ms),
                        ],
                        child: FrostedCard(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionTitle('Véhicule'),
                              const GoldDivider(),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _vehicleBrandC,
                                      decoration: _luxDec('Marque (ex: BMW)'),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _vehicleModelC,
                                      decoration: _luxDec('Modèle (ex: R1250)'),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _vehicleYearC,
                                      decoration: _luxDec('Année (ex: 2023)'),
                                      keyboardType: TextInputType.number,
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _licensePlateC,
                                      decoration: _luxDec('Immatriculation'),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _driverLicenseNumberC,
                                decoration: _luxDec('N° de permis'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 26),

                      // CTA principal bas de page (or, cohérent appbar)
                      SizedBox(
                        width: double.infinity,
                        child: GoldButton(
                          label: 'Enregistrer les modifications',
                          icon: Icons.save_rounded,
                          loading: _saving,
                          onTap: _saving ? () {} : _save,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Annuler',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
