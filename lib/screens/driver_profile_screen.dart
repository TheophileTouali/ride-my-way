// ignore_for_file: use_build_context_synchronously

import 'dart:math';
import 'dart:ui'; // BackdropFilter/blur, ImageFilter
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';
import '../providers/driver_provider.dart';
import '../models/driver_user.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';
import 'dart:io' as io show File;
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart'; // image + PDF
import 'package:url_launcher/url_launcher.dart'; // ouvrir PDF
import 'package:cloud_firestore/cloud_firestore.dart';

/// ----------
///  LUX KIT 2.0 — Billionaire Edition
/// ----------
class Lux {
  static const gold = AppColors.gold; // #FFD700
  static const deepGold = AppColors.deepGold; // #A87C00
  static const ink = Color(0xFF0E0E10);
  static const carbon = Color(0xFF0B0B0C);

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

/// Verre fumé + blur (ultra premium)
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

/// Bouton or premium
class GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  const GoldButton(
      {super.key, required this.label, required this.onTap, this.icon});
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
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hover = v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.black, size: 20),
                  const SizedBox(width: 10),
                ],
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

/// Halo doré respirant
class GoldHalo extends StatefulWidget {
  final double size;
  final Widget child;
  const GoldHalo({super.key, required this.child, this.size = 100});
  @override
  State<GoldHalo> createState() => _GoldHaloState();
}

class _GoldHaloState extends State<GoldHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) {
        final t = .55 + (.45 * c.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Lux.gold.withOpacity(.22 * t),
                blurRadius: 30 * t,
                spreadRadius: 2.2 * t,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Titre métal brossé
class MetallicTitle extends StatelessWidget {
  final String text;
  final double size;
  const MetallicTitle(this.text, {super.key, this.size = 22});
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

/// Ligne de séparation or brossé
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

/// Particules dorées très légères (visuel milliardaire, perf-safe)
class GoldParticles extends StatefulWidget {
  final int count;
  const GoldParticles({super.key, this.count = 18});
  @override
  State<GoldParticles> createState() => _GoldParticlesState();
}

class _GoldParticlesState extends State<GoldParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();
  final random = Random();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) {
        return CustomPaint(
          painter: _GoldParticlesPainter(c.value, widget.count),
          size: Size.infinite,
        );
      },
    );
  }
}

class _GoldParticlesPainter extends CustomPainter {
  final double t;
  final int count;
  _GoldParticlesPainter(this.t, this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(42);
    for (int i = 0; i < count; i++) {
      final baseX = rnd.nextDouble();
      final baseY = rnd.nextDouble();
      final phase = i / count;
      final x = (baseX + t * (.08 + phase * .02)) % 1.0;
      final y = (baseY + sin(2 * pi * (t + phase)) * .002) % 1.0;

      final pos = Offset(x * size.width, y * size.height);
      final r = 1.0 + (i % 3) * .6;
      final paint = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..color = Color.lerp(Lux.deepGold.withOpacity(.35),
            Lux.gold.withOpacity(.75), (i % 7) / 7)!;

      canvas.drawCircle(pos, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldParticlesPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// ----------
///  ECRAN
/// ----------
class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  // Anti-cache
  String _cacheBust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  String _extFromUrl(String url) {
    final q = url.split('?').first;
    final i = q.lastIndexOf('.');
    return (i >= 0 ? q.substring(i + 1) : '').toLowerCase();
  }

  bool _isPdfUrl(String url) {
    final ext = _extFromUrl(url);
    return ext == 'pdf' ||
        url.toLowerCase().contains('content-type=application/pdf');
  }

  bool _isImageUrl(String url) {
    if (_isPdfUrl(url)) return false;
    final ext = _extFromUrl(url);
    if (const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) return true;
    final lower = url.toLowerCase();
    return lower.contains('alt=media') || lower.contains('firebasestorage');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Impossible d’ouvrir $url';
    }
  }

  Future<void> _previewImage(BuildContext context, String url) async {
    final bust = _cacheBust(url);
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  bust,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('Impossible d’afficher l’image',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeVehiclePhoto(BuildContext context) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final user = driverProvider.user;
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final isPng = picked.name.toLowerCase().endsWith('.png') ||
          picked.path.toLowerCase().endsWith('.png');
      final ext = isPng ? 'png' : 'jpg';
      final contentType = isPng ? 'image/png' : 'image/jpeg';

      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'vehicle_$ts.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('drivers_data/${user.uid}/$fileName');

      final metadata = SettableMetadata(
        contentType: contentType,
        cacheControl: 'no-cache, max-age=0',
      );

      UploadTask task;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        task = ref.putData(bytes, metadata);
      } else {
        final file = io.File(picked.path);
        task = ref.putFile(file, metadata);
      }

      final snap = await task;
      final url = await snap.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .set({'vehiclePhotoUrl': url}, SetOptions(merge: true));

      driverProvider.setUser(DriverUser(
        uid: user.uid,
        firstName: user.firstName,
        lastName: user.lastName,
        email: user.email,
        phone: user.phone,
        photoUrl: user.photoUrl,
        address: user.address,
        birthdate: user.birthdate,
        vehicleType: user.vehicleType,
        vehicleBrand: user.vehicleBrand,
        vehicleModel: user.vehicleModel,
        vehicleYear: user.vehicleYear,
        licensePlate: user.licensePlate,
        driverLicenseNumber: user.driverLicenseNumber,
        vehiclePhotoUrl: url,
        documents: user.documents,
      ));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.black87,
            content: Text('✅ Photo du véhicule mise à jour',
                style: TextStyle(color: AppColors.gold)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black87,
            content: Text('Erreur lors de la mise à jour : $e',
                style: const TextStyle(color: Colors.redAccent)),
          ),
        );
      }
    }
  }

  Future<void> _changeDriverPhoto(BuildContext context) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final current = driverProvider.user;
    if (current == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final isPng = picked.name.toLowerCase().endsWith('.png') ||
          picked.path.toLowerCase().endsWith('.png');
      final ext = isPng ? 'png' : 'jpg';
      final contentType = isPng ? 'image/png' : 'image/jpeg';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'profile_$ts.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('drivers_data/${current.uid}/$fileName');

      final metadata = SettableMetadata(
          contentType: contentType, cacheControl: 'no-cache, max-age=0');

      UploadTask task;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        task = ref.putData(bytes, metadata);
      } else {
        final file = io.File(picked.path);
        task = ref.putFile(file, metadata);
      }

      final snap = await task;
      final url = await snap.ref.getDownloadURL();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .set({'photoUrl': url}, SetOptions(merge: true));
      }
      try {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      } catch (_) {}

      driverProvider.setUser(
        DriverUser(
          uid: current.uid,
          firstName: current.firstName,
          lastName: current.lastName,
          email: current.email,
          phone: current.phone,
          photoUrl: url,
          address: current.address,
          birthdate: current.birthdate,
          vehicleType: current.vehicleType,
          vehicleBrand: current.vehicleBrand,
          vehicleModel: current.vehicleModel,
          vehicleYear: current.vehicleYear,
          licensePlate: current.licensePlate,
          driverLicenseNumber: current.driverLicenseNumber,
          vehiclePhotoUrl: current.vehiclePhotoUrl,
          documents: current.documents,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.black87,
            content: Text('✅ Photo de profil mise à jour',
                style: TextStyle(color: AppColors.gold)),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.black87,
            content: Text('Erreur lors de la mise à jour : $e',
                style: const TextStyle(color: Colors.redAccent)),
          ),
        );
      }
    }
  }

  Future<void> _uploadDocument(
      BuildContext context, String fieldKey, String label) async {
    final userProvider = Provider.of<DriverProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf'],
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.single;
    final bytes = f.bytes;
    final ext = (f.extension ?? '').toLowerCase().trim();
    final fileName =
        '${fieldKey}_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'bin' : ext}';

    final ref =
        FirebaseStorage.instance.ref('drivers_data/${user.uid}/$fileName');
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)
            ? (ext == 'jpg' ? 'image/jpeg' : 'image/$ext')
            : 'application/octet-stream');

    final metadata = SettableMetadata(
      contentType: contentType,
      cacheControl: 'public, max-age=31536000, immutable',
    );

    UploadTask task;
    if (bytes != null) {
      task = ref.putData(bytes, metadata);
    } else if (f.path != null) {
      task = ref.putFile(io.File(f.path!), metadata);
    } else {
      return;
    }

    final snap = await task;
    final url = await snap.ref.getDownloadURL();

    await userProvider.updateDriverDocument(fieldKey, url);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          content: Text("$label ajouté avec succès",
              style: const TextStyle(color: AppColors.gold)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isProfileComplete(DriverUser user) {
    final requiredKeys = [
      'driverLicenseUrl',
      'registrationUrl',
      'vehicleInsuranceUrl',
      'proInsuranceUrl',
      'technicalInspectionUrl',
      'maintenanceInvoiceUrl',
      'ribUrl',
      'idCardUrl',
    ];
    final documents = user.documents ?? {};
    for (final key in requiredKeys) {
      if (!(documents.containsKey(key) &&
          documents[key] != null &&
          documents[key].toString().isNotEmpty)) {
        return false;
      }
    }
    return true;
  }

  /// -------- SUPPRESSION DE COMPTE (Apple 5.1.1(v)) --------
  Future<void> _confirmAndDeleteAccount(BuildContext context) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.black87,
          content: Text(
            "Aucun utilisateur connecté.",
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111118),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          "Supprimer mon compte",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          "Cette action supprimera définitivement votre compte Ride My Way, "
          "ainsi que vos données de profil conducteur. Cette opération est irréversible.\n\n"
          "Voulez-vous vraiment continuer ?",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              "Supprimer",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Loader plein écran
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      ),
    );

    try {
      final uid = user.uid;

      // Suppression des documents principaux Firestore liés au conducteur
      final batch = FirebaseFirestore.instance.batch();
      final driverDoc =
          FirebaseFirestore.instance.collection('drivers').doc(uid);
      batch.delete(driverDoc);

      // Si tu as aussi un profil global "users", tu peux ajouter :
      // final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      // batch.delete(userDoc);

      await batch.commit();

      // Suppression du compte Firebase Auth
      await user.delete();

      // Nettoyage provider + navigation
      driverProvider.logout();

      Navigator.of(context).pop(); // ferme le loader

      context.go('/login-driver');
    } on FirebaseAuthException catch (e) {
      Navigator.of(context).pop(); // ferme le loader

      String message = "Erreur lors de la suppression du compte.";
      if (e.code == 'requires-recent-login') {
        message =
            "Pour des raisons de sécurité, merci de vous reconnecter avant de supprimer votre compte, puis réessayez.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          content: Text(
            message,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // ferme le loader

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          content: Text(
            "Une erreur est survenue : $e",
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;

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
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/driver-home'),
        ),
        title: const MetallicTitle("Mon Profil Conducteur", size: 22),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withOpacity(.22)),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fond ultra premium : dégradé profond + légères particules dorées
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
              child: IgnorePointer(child: GoldParticles(count: 16))),

          // Contenu
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _content(context, user),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// --- CONTENT (colonne) ---
  Widget _content(BuildContext context, DriverUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // HEADER — avatar + infos + badge
        Animate(
          effects: [
            FadeEffect(duration: 500.ms),
            MoveEffect(begin: const Offset(0, 20), duration: 500.ms),
          ],
          child: FrostedCard(
            margin: const EdgeInsets.only(bottom: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _changeDriverPhoto(context),
                  child: GoldHalo(
                    size: 104,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: Lux.gradientGold,
                      ),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 46,
                            backgroundImage: (user.photoUrl != null &&
                                    user.photoUrl!.isNotEmpty)
                                ? NetworkImage(_cacheBust(user.photoUrl!))
                                : const AssetImage(
                                        'assets/images/user_placeholder.png')
                                    as ImageProvider,
                            backgroundColor: Colors.grey.shade900,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.edit,
                                  size: 14, color: AppColors.gold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MetallicTitle(user.fullName, size: 24),
                      const SizedBox(height: 6),
                      _infoLine(
                          icon: Icons.email_rounded,
                          value: user.email ?? '',
                          color: Colors.white70),
                      _infoLine(
                          icon: Icons.phone_android_rounded,
                          value: user.phone ?? '',
                          color: AppColors.deepGold),
                      if (user.address?.isNotEmpty ?? false)
                        _infoLine(
                            icon: Icons.location_on_rounded,
                            value: user.address!,
                            color: Colors.white60),
                      if (user.birthdate?.isNotEmpty ?? false)
                        _infoLine(
                            icon: Icons.cake_outlined,
                            value: user.birthdate!,
                            color: Colors.white54),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _statusChip(_isProfileComplete(user)),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // VEHICULE
        Animate(
          effects: [
            FadeEffect(duration: 500.ms),
            MoveEffect(begin: const Offset(0, 30), duration: 500.ms),
          ],
          child: FrostedCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _changeVehiclePhoto(context),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 116,
                          height: 88,
                          child: Image.network(
                            (user.vehiclePhotoUrl ?? '').isNotEmpty
                                ? _cacheBust(user.vehiclePhotoUrl!)
                                : '',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/vehicles_motos_premium.png',
                              fit: BoxFit.cover,
                            ),
                            loadingBuilder: (context, child, p) {
                              if (p == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  value: p.expectedTotalBytes != null
                                      ? p.cumulativeBytesLoaded /
                                          (p.expectedTotalBytes ?? 1)
                                      : null,
                                  color: AppColors.deepGold,
                                  strokeWidth: 2,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.edit,
                              size: 14, color: AppColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (user.vehicleBrand?.isNotEmpty ?? false)
                        const SizedBox(height: 2),
                      if (user.vehicleBrand?.isNotEmpty ?? false)
                        MetallicTitle("Votre ${user.vehicleBrand!} est prête.",
                            size: 18),
                      if (user.vehicleYear?.isNotEmpty ?? false)
                        const SizedBox(height: 6),
                      if (user.vehicleYear?.isNotEmpty ?? false)
                        const Text(
                          "Modèle — entre style, puissance et précision.",
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 14,
                              fontStyle: FontStyle.italic),
                        ),
                      if (!(user.vehicleBrand?.isNotEmpty ?? false) &&
                          !(user.vehicleYear?.isNotEmpty ?? false))
                        const Text(
                          "Ajoutez votre véhicule pour mettre en valeur votre style de conduite.",
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // DOCUMENTS
        FrostedCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MetallicTitle("📄 Vos documents", size: 18),
              const SizedBox(height: 10),
              const GoldDivider(),
              const SizedBox(height: 8),
              ..._buildDocumentList(context, user),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const GoldDivider(),
        const SizedBox(height: 20),

        // CTA
        _premiumCTA(context),

        const SizedBox(height: 26),

        // PARAMÈTRES
        _settingsCard(
          context: context,
          onChangePassword: () => context.push(
            Uri(
              path: '/reset-password',
              queryParameters: {'from': '/driver-profile', 'role': 'driver'},
            ).toString(),
          ),
          onLogout: () {
            Provider.of<DriverProvider>(context, listen: false).logout();
            context.go('/login-driver');
          },
          onDeleteAccount: () => _confirmAndDeleteAccount(context),
        ),
      ],
    );
  }

  Widget _statusChip(bool verified) {
    final color = verified ? Colors.greenAccent : Colors.redAccent;
    final icon = verified ? Icons.verified : Icons.error_outline;
    final text = verified ? 'Profil vérifié' : 'Profil incomplet';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: color.withOpacity(.10),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  List<Widget> _buildDocumentList(BuildContext context, dynamic user) {
    final documents = [
      {"key": "driverLicenseUrl", "label": "Permis de conduire"},
      {"key": "registrationUrl", "label": "Carte grise"},
      {"key": "vehicleInsuranceUrl", "label": "Assurance du véhicule"},
      {"key": "proInsuranceUrl", "label": "Assurance professionnelle"},
      {"key": "technicalInspectionUrl", "label": "Contrôle technique"},
      {"key": "maintenanceInvoiceUrl", "label": "Facture d'entretien"},
      {"key": "ribUrl", "label": "RIB"},
      {"key": "idCardUrl", "label": "Pièce d'identité"},
    ];

    return documents.map((doc) {
      final key = doc['key']!;
      final label = doc['label']!;
      final url = user.documents?[key];
      final hasUrl = url is String && url.isNotEmpty;

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LIGNE 1 — Statut + miniature + libellé (toujours lisible)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  hasUrl ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: hasUrl ? Colors.greenAccent : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),

                if (hasUrl && _isImageUrl(url)) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      _cacheBust(url),
                      width: 44,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 36,
                        color: Colors.black26,
                        child: const Icon(Icons.broken_image,
                            size: 18, color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // Libellé toujours sur 1 ligne, ellipsis
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUrl ? Colors.white : Colors.white54,
                      fontSize: 15,
                      fontWeight: hasUrl ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // LIGNE 2 — Actions (ne débordent jamais)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasUrl)
                  _pillButton(
                    'Voir',
                    icon: Icons.visibility_rounded,
                    onTap: () => _isPdfUrl(url)
                        ? _openUrl(url)
                        : _previewImage(context, url),
                  ),
                const SizedBox(width: 8),
                _pillButton(
                  hasUrl ? 'Modifier' : 'Ajouter',
                  icon: Icons.edit_rounded,
                  onTap: () => _uploadDocument(context, key, label),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _pillButton(String text,
      {IconData? icon, required VoidCallback onTap}) {
    final showShort = text.length <= 5; // “Voir”, “RIB”, “Modif.” etc.

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.deepGold.withOpacity(.6)),
          color: Colors.black.withOpacity(.20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.deepGold),
              if (showShort) const SizedBox(width: 6),
            ],
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                color: AppColors.deepGold,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoLine(
      {required IconData icon, required String value, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withOpacity(0.78)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 14, color: color, fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------
///  CTA & SETTINGS
/// ----------
Widget _premiumCTA(BuildContext context) {
  return GoldButton(
    label: 'Modifier mes informations',
    icon: Icons.edit_rounded,
    onTap: () => context.push('/edit-driver-profile'),
  );
}

Widget _settingsCard({
  required BuildContext context,
  required VoidCallback onChangePassword,
  required VoidCallback onLogout,
  required VoidCallback onDeleteAccount,
}) {
  Widget row({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final c = danger ? Colors.redAccent : color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    danger ? Colors.red.withOpacity(.12) : c.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withOpacity(.35)),
              ),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color:
                      danger ? Colors.redAccent : Colors.white.withOpacity(.92),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(.40)),
          ],
        ),
      ),
    );
  }

  return FrostedCard(
    child: Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: MetallicTitle('Paramètres du compte', size: 18),
        ),
        const SizedBox(height: 10),
        const GoldDivider(),
        row(
          icon: Icons.lock_reset_rounded,
          label: 'Modifier le mot de passe',
          color: AppColors.deepGold,
          onTap: onChangePassword,
        ),
        const GoldDivider(),
        row(
          icon: Icons.logout_rounded,
          label: 'Se déconnecter',
          color: Colors.redAccent,
          onTap: onLogout,
          danger: true,
        ),
        const GoldDivider(),
        row(
          icon: Icons.delete_forever_rounded,
          label: 'Supprimer mon compte',
          color: Colors.redAccent,
          onTap: onDeleteAccount,
          danger: true,
        ),
      ],
    ),
  );
}
