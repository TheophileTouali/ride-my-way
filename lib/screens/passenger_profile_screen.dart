import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';
import '../providers/user_provider.dart';
import 'dart:ui' as ui;

/// —————————————————————————————————————————————————————————
/// 1) Premium utils: dégradés or + glass + glow
/// —————————————————————————————————————————————————————————
class Premium {
  static const goldGradient = LinearGradient(
    colors: [AppColors.gold, AppColors.deepGold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxShadow goldGlow([double blur = 20, double opacity = .22]) =>
      BoxShadow(
        color: AppColors.gold.withOpacity(opacity),
        blurRadius: blur,
        offset: const Offset(0, 8),
      );

  /// Conservé pour compat’ (utilisé par _trustSafetyShowcase)
  static BoxDecoration glass({double radius = 24, double opacity = .55}) =>
      BoxDecoration(
        color: Colors.black.withOpacity(opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.30),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      );
}

/// Icône dorée (dégradé RMV + option glow)
class GoldIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final EdgeInsets padding;
  final bool glow;
  const GoldIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.padding = EdgeInsets.zero,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, color: Colors.white, size: size);
    final masked = ShaderMask(
      shaderCallback: (rect) => Premium.goldGradient.createShader(rect),
      blendMode: BlendMode.srcIn,
      child: child,
    );
    return Padding(
      padding: padding,
      child: glow
          ? DecoratedBox(
              decoration: BoxDecoration(boxShadow: [Premium.goldGlow(16, .23)]),
              child: masked,
            )
          : masked,
    );
  }
}

/// Texte en dégradé or
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => Premium.goldGradient.createShader(r),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class PassengerProfileScreen extends StatefulWidget {
  const PassengerProfileScreen({super.key});

  @override
  State<PassengerProfileScreen> createState() => _PassengerProfileScreenState();
}

class _PassengerProfileScreenState extends State<PassengerProfileScreen> {
  /// Toujours le même bucket (évite les mélanges appspot/firebasestorage)
  final FirebaseStorage storage = FirebaseStorage.instanceFor(
    bucket: 'gs://ride-my-way-7f258.firebasestorage.app',
  );

  final _picker = ImagePicker();

  /// Aperçu immédiat après upload (avant que Firestore ne se propage)
  String? _tempPhotoUrl;

  /// Ajoute un paramètre pour casser le cache navigateur/CDN
  String _cacheBust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Upload avatar (Web + mobile), MAJ Firestore & Auth, suppression ancienne image.
  Future<void> _pickAndUploadImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Ancienne URL pour supprimer l'ancien fichier (best effort)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final String? oldUrl = userDoc.data()?['photoUrl'] as String?;

      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'users_data/${user.uid}/profile_$ts.png';
      final ref = storage.ref().child(path);

      UploadTask task;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        task = ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      } else {
        task = ref.putFile(
            File(picked.path), SettableMetadata(contentType: 'image/png'));
      }

      await task.whenComplete(() {});
      final newUrl = (await ref.getDownloadURL()).trim();

      // 🔥 Aperçu instantané
      if (mounted) {
        context.read<UserProvider>().updateAvatarUrl(newUrl);
        setState(() => _tempPhotoUrl = newUrl);
      }

      // Firestore + FirebaseAuth (photoURL)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': newUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.updatePhotoURL(newUrl);

      // Supprimer l’ancienne image (optionnel)
      if (oldUrl != null && oldUrl.isNotEmpty) {
        try {
          await storage.refFromURL(oldUrl).delete();
        } catch (e) {
          debugPrint('ℹ️ Ancienne photo non supprimée: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Photo de profil mise à jour')),
        );
      }
    } catch (e, st) {
      debugPrint('❌ Upload avatar failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la mise à jour de la photo.'),
          ),
        );
      }
    }
  }

  // ✅ SUPPRESSION DE COMPTE — Apple 5.1.1(v)
  Future<void> _confirmAndDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          "Cette action supprimera définitivement votre compte Ride My Way ainsi que vos données de profil.\n\n"
          "Cette opération est irréversible.\n\n"
          "Voulez-vous continuer ?",
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.3),
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

    // Loader
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

      // 1) Supprime Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 2) Supprime Auth
      await user.delete();

      // 3) Logout local + redirection
      if (mounted) {
        context.read<UserProvider>().logout();
        Navigator.of(context).pop(); // close loader
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) Navigator.of(context).pop(); // close loader

      String msg = "Erreur lors de la suppression du compte.";
      if (e.code == 'requires-recent-login') {
        msg =
            "Pour des raisons de sécurité, veuillez vous reconnecter puis réessayez la suppression.";
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          content: Text(msg, style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // close loader
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black87,
          content: Text("Une erreur est survenue : $e",
              style: const TextStyle(color: Colors.redAccent)),
        ),
      );
    }
  }

  // —————————————————————————————————————————————————————————
  // HEADER ULTRA-PREMIUM — version alignée + anti-overflow
  // —————————————————————————————————————————————————————————
  Widget _premiumHeader(
    String? bustUrl,
    Map<String, dynamic> data,
    VoidCallback onChangePhoto,
  ) {
    final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
    final email = (data['email'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: _SoftGlass(
        radius: 24,
        outerShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.08),
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 14),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (r) => Premium.goldGradient.createShader(r),
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      name.isEmpty ? 'Invité' : name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.w800,
                        fontSize: 30,
                        height: 1.12,
                        letterSpacing: .2,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                              color: Colors.black54,
                              offset: Offset(0, 1.4),
                              blurRadius: 3)
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email.isEmpty ? '—' : email,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.95),
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      letterSpacing: .15,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 2)
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (_, c) {
                    final scale = c.maxWidth >= 380 ? 1.15 : 1.0;
                    return Column(
                      children: [
                        Transform.scale(
                          scale: scale,
                          child:
                              _AvatarRing(url: bustUrl, onTap: onChangePhoto),
                        ),
                        const SizedBox(height: 10),
                        _SoftEditButton(
                            onTap: () => context.go('/edit-profile')),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  Builder(builder: (_) {
                    String _s(dynamic v) =>
                        (v is String) ? v : (v?.toString() ?? '');
                    num? _num(dynamic v) =>
                        (v is num) ? v : num.tryParse('${v ?? ''}');
                    DateTime? _ts(dynamic v) {
                      if (v == null) return null;
                      if (v is Timestamp) return v.toDate();
                      if (v is String) return DateTime.tryParse(v);
                      return null;
                    }

                    final kyc = (data['kyc'] as Map?)?.cast<String, dynamic>();
                    final verified = (kyc?['status'] == 'verified') ||
                        _s(data['identityCardUrl']).isNotEmpty;

                    final created = _ts(data['createdAt']);
                    final membreDepuis = created == null
                        ? null
                        : '${created.month.toString().padLeft(2, '0')}/${created.year}';

                    final birth = _ts(data['birthdate']);
                    int? age;
                    if (birth != null) {
                      final now = DateTime.now();
                      var a = now.year - birth.year;
                      if (now.month < birth.month ||
                          (now.month == birth.month && now.day < birth.day))
                        a--;
                      if (a >= 0 && a < 120) age = a;
                    }

                    final rating = _num(data['rating']);
                    final tier =
                        _s(data['tier']).isEmpty ? null : _s(data['tier']);
                    final reco = _num(data['recommendPct']);

                    final chips = <Widget>[
                      if (verified)
                        const _SoftChip(
                          icon: Icons.verified_rounded,
                          label: 'Profil vérifié',
                          accent: AppColors.gold,
                        ),
                      if (age != null)
                        _SoftChip(icon: Icons.cake_rounded, label: '$age ans'),
                      if (membreDepuis != null)
                        _SoftChip(
                          icon: Icons.event_available_rounded,
                          label: 'Membre depuis $membreDepuis',
                        ),
                      if (rating != null)
                        _SoftChip(
                          icon: Icons.star_rate_rounded,
                          label: '${rating.clamp(0, 5).toStringAsFixed(1)} ★',
                        ),
                      if (reco != null)
                        _SoftChip(
                          icon: Icons.thumb_up_alt_rounded,
                          label: 'Recommandé ${reco.round()}%',
                        ),
                      if (tier != null)
                        _SoftChip(icon: Icons.diamond_rounded, label: tier),
                    ];

                    return Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: chips,
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trustSafetyShowcase(Map<String, dynamic> userData) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: Premium.glass(opacity: .50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              GoldIcon(Icons.shield_rounded, size: 22, glow: true),
              SizedBox(width: 8),
              GradientText(
                'Confiance & Sécurité',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _trustPill(
            icon: Icons.credit_card_rounded,
            title: 'Paiements sécurisés',
            subtitle:
                'Pré-autorisation Stripe • 3-D Secure • Données chiffrées',
            ok: true,
          ),
          const SizedBox(height: 10),
          _trustPill(
            icon: Icons.verified_rounded,
            title: 'Chauffeurs vérifiés',
            subtitle: 'Identité contrôlée • Dossier validé • Note ≥ 4,8/5',
            ok: true,
          ),
          const SizedBox(height: 10),
          _trustPill(
            icon: Icons.lock_rounded,
            title: 'Protection des données (RGPD)',
            subtitle: 'Stockage UE • Accès strictement limité',
            ok: true,
          ),
        ],
      ),
    );
  }

  Widget _trustPill({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool ok,
  }) {
    final rightIcon =
        ok ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded;
    final rightColor = ok ? Colors.greenAccent : Colors.amberAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.25),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          GoldIcon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    )),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12.5, height: 1.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(rightIcon, size: 20, color: rightColor),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _personalInfoLine(IconData icon, String label, String value) {
    final v = (value.isEmpty) ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GoldIcon(icon, size: 18, padding: const EdgeInsets.only(top: 2)),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: GradientText(
              v,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _preferenceItem(String label, dynamic value) {
    final isBool = value is bool;
    final display = isBool
        ? (value ? 'Oui' : 'Non')
        : (value?.toString().trim().isEmpty ?? true)
            ? '—'
            : value.toString();
    final isPositive = isBool ? value == true : display != '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          GoldIcon(
            isBool ? Icons.toggle_on_rounded : Icons.check_circle_rounded,
            size: 18,
            glow: isPositive,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GradientText(
            display,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isPositive ? AppColors.gold : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: Premium.glass(opacity: .55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              GoldIcon(Icons.settings, size: 18, glow: true),
              SizedBox(width: 8),
              GradientText(
                'Actions du compte',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            final isWide = c.maxWidth > 520;
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 2 : 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 56,
              ),
              children: [
                _goldActionButton(
                  icon: Icons.lock_reset_rounded,
                  label: 'Modifier le mot de passe',
                  onTap: () => context.push(
                    Uri(
                      path: '/reset-password',
                      queryParameters: {
                        'from': '/profile',
                        'role': 'passenger'
                      },
                    ).toString(),
                  ),
                ),
                _goldActionButton(
                  icon: Icons.edit,
                  label: 'Modifier mes informations',
                  onTap: () => context.go('/edit-profile'),
                ),
                _goldActionButton(
                  icon: Icons.tune_rounded,
                  label: 'Modifier mes préférences',
                  onTap: () => context.push('/preferences-edit'),
                ),
                _dangerActionButton(
                  icon: Icons.logout_rounded,
                  label: 'Se déconnecter',
                  onTap: () {
                    Provider.of<UserProvider>(context, listen: false).logout();
                    context.go('/login');
                  },
                ),
                // ✅ Apple requirement
                _dangerActionButton(
                  icon: Icons.delete_forever_rounded,
                  label: 'Supprimer mon compte',
                  onTap: _confirmAndDeleteAccount,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _goldActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.deepGold.withOpacity(.20),
        child: Ink(
          decoration: BoxDecoration(
            gradient: Premium.goldGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [Premium.goldGlow(18, .28)],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GoldIcon(icon, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.black,
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

  /// ✅ FIX: utilise vraiment icon + label (avant c’était hardcodé)
  Widget _dangerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: Colors.redAccent.withOpacity(.10),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: Colors.redAccent.withOpacity(.7), width: 1.4),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GoldIcon(icon, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.redAccent,
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

  // —————————————————————————————————————————————————————————
  // BUILD
  // —————————————————————————————————————————————————————————
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const GoldIcon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.go('/home'),
          tooltip: 'Retour',
        ),
        centerTitle: true,
        title: const GradientText(
          'Mon Profil',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: uid == null
          ? const Center(
              child:
                  Text('Non connecté', style: TextStyle(color: Colors.white70)),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  );
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(
                    child: Text('Profil introuvable',
                        style: TextStyle(color: Colors.white70)),
                  );
                }

                final data = snap.data!.data() ?? {};
                final firestorePhoto = (data['photoUrl'] as String?) ?? '';

                if (_tempPhotoUrl != null && _tempPhotoUrl == firestorePhoto) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tempPhotoUrl = null);
                  });
                }

                final effectivePhoto = (_tempPhotoUrl?.isNotEmpty ?? false)
                    ? _tempPhotoUrl!
                    : firestorePhoto;

                final bust =
                    effectivePhoto.isEmpty ? null : _cacheBust(effectivePhoto);

                return Animate(
                  effects: [
                    FadeEffect(duration: 300.ms),
                    MoveEffect(begin: const Offset(0, 16), duration: 300.ms),
                  ],
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _premiumHeader(bust, data, _pickAndUploadImage),
                        const SizedBox(height: 18),
                        _trustSafetyShowcase(data),
                        const SizedBox(height: 24),
                        _sectionCard(
                          title: Row(
                            children: const [
                              GoldIcon(Icons.person_rounded,
                                  size: 18, glow: true),
                              SizedBox(width: 8),
                              GradientText(
                                'Informations personnelles',
                                style: TextStyle(
                                  fontFamily: 'PlayfairDisplay',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          children: [
                            _personalInfoLine(Icons.location_on, 'Adresse',
                                (data['address'] ?? '').toString()),
                            const Divider(color: Colors.white10, height: 28),
                            _personalInfoLine(
                              Icons.cake,
                              'Date de naissance',
                              (() {
                                final ts = data['birthdate'];
                                if (ts is Timestamp) {
                                  return ts
                                      .toDate()
                                      .toString()
                                      .split(' ')
                                      .first;
                                }
                                return '';
                              })(),
                            ),
                            const Divider(color: Colors.white10, height: 28),
                            _personalInfoLine(Icons.phone_android_rounded,
                                'Téléphone', (data['phone'] ?? '').toString()),
                          ],
                        ),
                        const SizedBox(height: 32),
                        _actionsCard(context),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Carte verre dépoli très douce (optimisée)
class _SoftGlass extends StatelessWidget {
  const _SoftGlass({
    required this.child,
    this.radius = 20,
    this.outerShadow,
  });
  final Widget child;
  final double radius;
  final List<BoxShadow>? outerShadow;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: outerShadow),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(.06),
                      Colors.white.withOpacity(.03)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.46),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: Colors.white.withOpacity(.07)),
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar avec anneau doré soft
class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.url, required this.onTap});
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Photo de profil. Appuyer pour changer.',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 98,
              height: 98,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: Premium.goldGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(.22),
                      blurRadius: 26,
                      spreadRadius: 1.2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: (url == null || url!.isEmpty)
                        ? Image.asset('assets/images/user_placeholder.png',
                            fit: BoxFit.cover)
                        : Image.network(
                            url!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
              ),
            ),
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withOpacity(.22),
                  width: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip “ultra soft”
class _SoftChip extends StatelessWidget {
  const _SoftChip({required this.icon, required this.label, this.accent});
  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.20),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c.withOpacity(.95)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(.95),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            letterSpacing: .1,
          ),
        ),
      ]),
    );
  }
}

/// Bouton “Éditer” tout en finesse
class _SoftEditButton extends StatelessWidget {
  const _SoftEditButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.edit, size: 16, color: AppColors.gold),
        label: const Text(
          'Éditer',
          style: TextStyle(
            color: AppColors.gold,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.gold.withOpacity(.55), width: 1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          backgroundColor: Colors.black.withOpacity(.20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          shadowColor: AppColors.gold.withOpacity(.12),
          elevation: 0,
        ),
      ),
    );
  }
}
