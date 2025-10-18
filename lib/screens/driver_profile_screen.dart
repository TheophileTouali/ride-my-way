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
import 'package:flutter/foundation.dart'; // pour kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart'; // pour choisir image + PDF
import 'package:url_launcher/url_launcher.dart'; // pour ouvrir PDF dans le navigateur
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  // Anti-cache (miniature/preview à jour)
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
    // Heuristique Firebase
    final lower = url.toLowerCase();
    return lower.contains('alt=media') || lower.contains('firebasestorage');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Impossible d’ouvrir $url';
    }
  }

  /// Aperçu image zoomable en plein écran
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
      // Déduction extension & content-type
      final isPng = picked.name.toLowerCase().endsWith('.png') ||
          picked.path.toLowerCase().endsWith('.png');
      final ext = isPng ? 'png' : 'jpg';
      final contentType = isPng ? 'image/png' : 'image/jpeg';

      // Upload dans Storage (chemin horodaté pour casser le cache)
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

      // 1) MAJ Firestore au bon endroit (champ top-level)
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .set({'vehiclePhotoUrl': url}, SetOptions(merge: true));

      // 2) MAJ immédiate du modèle local (pour rafraîchir l’UI)
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
        vehiclePhotoUrl: url, // ⬅️ on remplace par la nouvelle URL
        documents: user.documents,
      ));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Photo du véhicule mise à jour')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour : $e')),
        );
      }
    }
  }

// Upload / changement de la photo de profil
  Future<void> _changeDriverPhoto(BuildContext context) async {
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
      final fileName = 'profile_$ts.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('drivers_data/${user.uid}/$fileName');

      final metadata = SettableMetadata(
        contentType: contentType,
        // important to beat caches:
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

      // 1) Update top-level photoUrl in Firestore
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .set({'photoUrl': url}, SetOptions(merge: true));
      }

      // 2) Optional but nice: update Auth profile photo too
      try {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      } catch (_) {}

      // 3) Update the local provider user so UI refreshes right away
      final current = driverProvider.user!;
      driverProvider.setUser(
        DriverUser(
          uid: current.uid,
          firstName: current.firstName,
          lastName: current.lastName,
          email: current.email,
          phone: current.phone,
          photoUrl: url, // <- updated
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
            content: Text('✅ Photo de profil mise à jour'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la mise à jour : $e')),
        );
      }
    }
  }

  Future<void> _uploadDocument(
      BuildContext context, String fieldKey, String label) async {
    final userProvider = Provider.of<DriverProvider>(context, listen: false);
    final user = userProvider.user;
    if (user == null) return;

    // Choisir image **ou** PDF
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true, // requis sur Web
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf'],
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.single;
    final bytes = f.bytes; // Uint8List? (Web/Desktop/Mobile si withData)
    final ext = (f.extension ?? '').toLowerCase().trim();
    final fileName =
        '${fieldKey}_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'bin' : ext}';

    final ref =
        FirebaseStorage.instance.ref('drivers_data/${user.uid}/$fileName');
    final contentType = ext == 'pdf'
        ? 'application/pdf'
        : (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)
            ? 'image/$ext'
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
          content: Text("$label ajouté avec succès",
              style: const TextStyle(color: AppColors.gold)),
          backgroundColor: Colors.grey[900],
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

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<DriverProvider>(context).user;
    print("🧑‍🚗 Profil chargé : ${user?.photoUrl}");
    print("🚗 Photo véhicule : ${user?.vehiclePhotoUrl}");

    if (user == null) {
      Future.microtask(() => context.go('/login-driver'));
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/driver-home'),
        ),
        centerTitle: true,
        title: const Text(
          "Mon Profil Conducteur",
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // BLOC 1 — Profil conducteur premium
              Animate(
                effects: [
                  FadeEffect(duration: 500.ms),
                  MoveEffect(begin: const Offset(0, 20), duration: 500.ms),
                ],
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppColors.gold, AppColors.deepGold],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onTap: () => _changeDriverPhoto(context),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [AppColors.gold, AppColors.deepGold],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.gold.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 42,
                                  backgroundImage: (user.photoUrl != null &&
                                          user.photoUrl!.isNotEmpty)
                                      ? NetworkImage(_cacheBust(user.photoUrl!))
                                      : const AssetImage(
                                              'assets/images/user_placeholder.png')
                                          as ImageProvider,
                                  backgroundColor: Colors.grey.shade900,
                                ),

                                // Petit badge crayon en bas à droite (indice visuel)
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
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                                fontFamily: 'PlayfairDisplay',
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _infoLine(
                                icon: Icons.email_rounded,
                                value: user.email,
                                color: Colors.white70),
                            _infoLine(
                                icon: Icons.phone_android_rounded,
                                value: user.phone,
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
                            _isProfileComplete(user)
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      color: Colors.green.withOpacity(0.08),
                                      border:
                                          Border.all(color: Colors.greenAccent),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified,
                                            size: 18,
                                            color: Colors.greenAccent),
                                        SizedBox(width: 6),
                                        Text(
                                          'Profil vérifié',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                      color: Colors.red.withOpacity(0.08),
                                      border:
                                          Border.all(color: Colors.redAccent),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.error_outline,
                                            size: 18, color: Colors.redAccent),
                                        SizedBox(width: 6),
                                        Text(
                                          'Profil incomplet',
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // BLOC 2 — Véhicule premium animé
              Animate(
                effects: [
                  FadeEffect(duration: 500.ms),
                  MoveEffect(begin: const Offset(0, 30), duration: 500.ms),
                ],
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 1,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onTap: () => _changeVehiclePhoto(context),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: 100,
                                  height: 80,
                                  child: Image.network(
                                    (user.vehiclePhotoUrl ?? '').isNotEmpty
                                        ? _cacheBust(user.vehiclePhotoUrl!)
                                        : '',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.asset(
                                        'assets/images/vehicles_motos_premium.png',
                                        fit: BoxFit.cover,
                                      );
                                    },
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value: loadingProgress
                                                      .expectedTotalBytes !=
                                                  null
                                              ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  (loadingProgress
                                                          .expectedTotalBytes ??
                                                      1)
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
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (user.vehicleBrand != null &&
                                user.vehicleBrand!.isNotEmpty)
                              Text(
                                "Votre ${user.vehicleBrand!} est prête à briller sur la route.",
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'PlayfairDisplay',
                                ),
                              ),
                            if (user.vehicleYear != null &&
                                user.vehicleYear!.isNotEmpty)
                              const SizedBox(height: 6),
                            if (user.vehicleYear != null &&
                                user.vehicleYear!.isNotEmpty)
                              Text(
                                "Modèle ${user.vehicleYear!} — entre style, puissance et précision.",
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            if ((user.vehicleBrand == null ||
                                    user.vehicleBrand!.isEmpty) &&
                                (user.vehicleYear == null ||
                                    user.vehicleYear!.isEmpty))
                              const Text(
                                "Ajoutez votre véhicule pour mettre en valeur votre style de conduite.",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // BLOC 3 — Documents premium
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "📄 Vos documents",
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._buildDocumentList(context, user),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              const Divider(color: Colors.white10),
              const SizedBox(height: 20),

              // CTA premium (remplace l'ancien ElevatedButton simple)
              _premiumCTA(context),

              const SizedBox(height: 26),

              // Paramètres du compte (carte premium)
              _settingsCard(
                context: context,
                onChangePassword: () => context.go('/reset-password'),
                onLogout: () {
                  Provider.of<DriverProvider>(context, listen: false).logout();
                  context.go('/login-driver');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.grey[900],
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade800),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              hasUrl ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: hasUrl ? Colors.greenAccent : Colors.redAccent,
              size: 20,
            ),
            const SizedBox(width: 10),

            // Miniature image (si image disponible)
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

            // Libellé du document
            Expanded(
              flex: 3,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasUrl ? Colors.white70 : Colors.white38,
                  fontSize: 15,
                  fontWeight: hasUrl ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Bouton "Voir"
            if (hasUrl)
              TextButton(
                onPressed: () => _isPdfUrl(url)
                    ? _openUrl(url)
                    : _previewImage(context, url),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.deepGold,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(50, 36),
                ),
                child: const Text('Voir'),
              ),

            // Bouton "Modifier"
            TextButton.icon(
              onPressed: () => _uploadDocument(context, key, label),
              icon: const Icon(Icons.edit_rounded,
                  size: 16, color: AppColors.deepGold),
              label: Text(
                hasUrl ? 'Modifier' : 'Ajouter',
                style: const TextStyle(color: AppColors.deepGold),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(70, 36),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _docLine(String title, bool isAdded) {
    return Row(
      children: [
        Icon(
          isAdded ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: isAdded ? Colors.greenAccent : Colors.redAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: isAdded ? Colors.white70 : Colors.white38,
              fontSize: 14,
              fontWeight: isAdded ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          isAdded ? "Ajouté" : "Manquant",
          style: TextStyle(
            color: isAdded ? Colors.greenAccent : Colors.redAccent,
            fontSize: 13,
            fontStyle: FontStyle.italic,
          ),
        )
      ],
    );
  }

  Widget _infoLine(
      {required IconData icon, required String value, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color.withOpacity(0.7)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Map<String, String> items) {
    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
          const SizedBox(height: 12),
          ...items.entries.map((e) => _infoRow(e.key, e.value)).toList(),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: Icon(icon, color: color ?? AppColors.gold),
      title: Text(label,
          style: TextStyle(color: color ?? AppColors.gold, fontSize: 15)),
      onTap: onTap,
      tileColor: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

Widget _premiumCTA(BuildContext context) {
  return Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.gold, AppColors.deepGold],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: AppColors.gold.withOpacity(0.35),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/edit-driver-profile'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.edit_rounded, color: AppColors.black, size: 20),
              SizedBox(width: 10),
              Text(
                'Modifier mes informations',
                style: TextStyle(
                  color: AppColors.black,
                  fontWeight: FontWeight.w700,
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

Widget _settingsCard({
  required BuildContext context,
  required VoidCallback onChangePassword,
  required VoidCallback onLogout,
}) {
  Widget tile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: danger
                    ? Colors.red.withOpacity(.12)
                    : color.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                        (danger ? Colors.redAccent : color).withOpacity(.35)),
              ),
              child: Icon(icon,
                  size: 18, color: danger ? Colors.redAccent : color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color:
                      danger ? Colors.redAccent : Colors.white.withOpacity(.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(.4)),
          ],
        ),
      ),
    );
  }

  return Container(
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.55),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.3),
          blurRadius: 16,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: const [
              Text(
                'Paramètres du compte',
                style: TextStyle(
                  color: AppColors.gold,
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Divider(color: Colors.white12, height: 1),
        tile(
          icon: Icons.lock_reset_rounded,
          label: 'Modifier le mot de passe',
          color: AppColors.deepGold,
          onTap: onChangePassword,
        ),
        const Divider(color: Colors.white12, height: 1),
        tile(
          icon: Icons.logout_rounded,
          label: 'Se déconnecter',
          color: Colors.redAccent,
          onTap: onLogout,
          danger: true,
        ),
      ],
    ),
  );
}
