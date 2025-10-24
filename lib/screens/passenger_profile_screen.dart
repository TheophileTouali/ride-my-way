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

      // 🔥 Aperçu instantané : on met à jour l'UI tout de suite
      if (mounted) setState(() => _tempPhotoUrl = newUrl);

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
            // ✅ centre tout le bloc
            child: ConstrainedBox(
              // ✅ largeur max pour un rendu propre
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // — Nom doré
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
                        fontSize: 30, // un peu plus grand
                        height: 1.12, letterSpacing: .2, color: Colors.white,
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

                  // — Email très lisible
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

                  // — Photo + bouton en dessous (photo légèrement plus grande sur écrans ≥380px)
                  LayoutBuilder(builder: (_, c) {
                    final scale =
                        c.maxWidth >= 380 ? 1.15 : 1.0; // ✅ grandit la photo
                    return Column(
                      children: [
                        Transform.scale(
                            scale: scale,
                            child: _AvatarRing(
                                url: bustUrl, onTap: onChangePhoto)),
                        const SizedBox(height: 10),
                        _SoftEditButton(
                            onTap: () => context.go('/edit-profile')),
                      ],
                    );
                  }),

                  const SizedBox(height: 16),

                  // — Chips centrés
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
                            accent: AppColors.gold),
                      if (age != null)
                        _SoftChip(icon: Icons.cake_rounded, label: '$age ans'),
                      if (membreDepuis != null)
                        _SoftChip(
                            icon: Icons.event_available_rounded,
                            label: 'Membre depuis $membreDepuis'),
                      if (rating != null)
                        _SoftChip(
                            icon: Icons.star_rate_rounded,
                            label:
                                '${rating.clamp(0, 5).toStringAsFixed(1)} ★'),
                      if (reco != null)
                        _SoftChip(
                            icon: Icons.thumb_up_alt_rounded,
                            label: 'Recommandé ${reco.round()}%'),
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

  Widget _goldChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.gold.withOpacity(.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.18),
            blurRadius: 8,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        GoldIcon(icon, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ]),
    );
  }

  Widget _okChip({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF34D399), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
              color: Color(0x5534D399), blurRadius: 10, offset: Offset(0, 4)),
        ],
        border: Border.all(color: Color(0xFF10B981)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 16, color: Colors.black),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ===================== TRUST & SAFETY — CHECKLIST PREMIUM =====================

  // Halo doré qui pulse (safe avec flutter_animate)
  Widget _haloIcon(IconData icon, {double size = 22}) {
    final halo = Container(
      width: size + 16,
      height: size + 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.gold.withOpacity(.18),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(
            begin: .95, end: 1.10, duration: 1200.ms, curve: Curves.easeInOut)
        .fade(begin: .6, end: 1.0, duration: 1200.ms);

    return Stack(alignment: Alignment.center, children: [
      halo,
      GoldIcon(icon, size: size, glow: true),
    ]);
  }

  // Pastille "engagement" — non cliquable
  Widget _trustPill({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool ok, // true => ✅ vert, false => ⏳ ambre
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

  // Ruban complet : lit l’état KYC pour "Documents vérifiés", le reste est un plus marque premium
  Widget _trustSafetyShowcase(Map<String, dynamic> userData) {
    // KYC: vérifié / en attente (fallback legacy identityCardUrl)
    final kyc = (userData['kyc'] as Map?)?.cast<String, dynamic>();
    final kycStatus = (kyc?['status'] as String?) ?? '';
    final hasLegacy =
        ((userData['identityCardUrl'] as String?) ?? '').isNotEmpty;
    final docsOk = kycStatus == 'verified';
    final docsPending = !docsOk && (kycStatus == 'pending' || hasLegacy);

    // docsPending non affiché pour éviter de donner un sentiment négatif en UI
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: Premium.glass(opacity: .50),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [SizedBox(width: 2)]),
          Row(children: const []),
          Row(
            children: [
              _haloIcon(Icons.shield_rounded, size: 22),
              const SizedBox(width: 8),
              const GradientText(
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
            icon: Icons.car_crash_rounded,
            title: 'Véhicules assurés & contrôlés',
            subtitle: 'Assurance à jour • Contrôles périodiques',
            ok: true,
          ),
          const SizedBox(height: 10),
          _trustPill(
            icon: Icons.lock_rounded,
            title: 'Protection des données (RGPD)',
            subtitle: 'Stockage UE • Accès strictement limité',
            ok: true,
          ),
          const SizedBox(height: 10),
          _trustPill(
            icon: Icons.share_location_rounded,
            title: 'Partage de trajet en temps réel',
            subtitle: 'Suivi live et partage sécurisé de l’itinéraire',
            ok: true,
          ),
          const SizedBox(height: 10),
          _trustPill(
            icon: Icons.support_agent_rounded,
            title: 'Assistance prioritaire',
            subtitle: 'Support réactif en cas d’imprévu',
            ok: true,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // —————————————————————————————————————————————————————————
  // UI helpers (section, infos, préférences, actions)
  // —————————————————————————————————————————————————————————
  Widget _sectionCard({required Widget title, required List<Widget> children}) {
    // version conservatrice (pas de changement de look brutal)
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

          // grille responsive (1 col sur mobile, 2 cols si >520px)
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

  /// Icône toujours or (exigence), mais outline "danger"
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
              children: const [
                GoldIcon(Icons.logout_rounded, size: 20), // icône or (branding)
                SizedBox(width: 10),
                Text(
                  'Se déconnecter',
                  style: TextStyle(
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

      /// 🔥 Lecture *en temps réel* du document utilisateur
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

                // Si Firestore a rattrapé l’aperçu local, on nettoie _tempPhotoUrl
                if (_tempPhotoUrl != null && _tempPhotoUrl == firestorePhoto) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _tempPhotoUrl = null);
                  });
                }

                // Priorité à l’aperçu local, sinon valeur Firestore
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
                        // —— Header + KPIs + Trust
                        _premiumHeader(bust, data, _pickAndUploadImage),
                        const SizedBox(height: 18),

                        _trustSafetyShowcase(data),

                        const SizedBox(height: 24),

                        // —— Infos personnelles
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

                        const SizedBox(height: 24),

                        // —— Préférences (logique existante, rendu premium)
                        Builder(builder: (_) {
                          // 1) Prefs depuis Firestore (nouveau modèle)
                          final Map<String, dynamic> prefsMap =
                              (data['preferences'] as Map?)
                                      ?.cast<String, dynamic>() ??
                                  {};

                          // 2) Fallback vers le provider (legacy déjà chargé en mémoire)
                          final legacy =
                              Provider.of<UserProvider>(context).preferences;

                          // Helpers d’affichage
                          String s(String key, {String? orElse}) {
                            final v = prefsMap[key];
                            if (v == null) return orElse ?? '—';
                            final str = v.toString().trim();
                            return str.isEmpty ? (orElse ?? '—') : str;
                          }

                          bool b(String key, {bool? orElse}) {
                            final v = prefsMap[key];
                            if (v is bool) return v;
                            return orElse ?? false;
                          }

                          String listStr(String key) {
                            final v = prefsMap[key];
                            if (v is List && v.isNotEmpty) {
                              return v.map((e) => e.toString()).join(', ');
                            }
                            return '—';
                          }

                          // ===== Conditions d'affichage côté PROFIL =====
                          bool showMusicStyle() =>
                              (prefsMap['music'] == true) &&
                              (s('ambiance') != 'Silencieux');
                          bool showTemperatureLevel() =>
                              (prefsMap['temperature'] == true);
                          bool showScentLevel() =>
                              (prefsMap['perfume'] == true);
                          bool isMoto() => s('vehicleType') == 'Moto';

                          Widget lineIf(
                                  bool cond, String label, dynamic value) =>
                              cond
                                  ? _preferenceItem(label, value)
                                  : const SizedBox.shrink();

                          // Valeurs avec fallback (compat descendante)
                          final ambiance =
                              s('ambiance', orElse: legacy.ambiance);
                          final musicOn = b('music', orElse: legacy.music);
                          final perfumeOn =
                              b('perfume', orElse: legacy.perfume);
                          final tempSwitchOn =
                              b('temperature', orElse: legacy.temperature);
                          final wifiOn = b('wifi', orElse: legacy.wifi);
                          final smokeFreeOn =
                              b('smokeFree', orElse: legacy.smokeFree);
                          final petsOn = b('pets', orElse: legacy.pets);

                          return _sectionCard(
                            title: Row(
                              children: const [
                                GoldIcon(Icons.headphones_rounded,
                                    size: 20, glow: true),
                                SizedBox(width: 8),
                                GradientText(
                                  'Vos préférences de trajet',
                                  style: TextStyle(
                                    fontFamily: 'PlayfairDisplay',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              // 1) Ambiance & confort intérieur
                              Row(
                                children: const [
                                  GoldIcon(Icons.directions_car_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Ambiance et confort intérieur',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Ambiance sonore (niveau de musique)',
                                  ambiance),
                              const SizedBox(height: 8),
                              lineIf(
                                showMusicStyle(),
                                'Style musical (genre favori)',
                                s('musicStyle', orElse: '—'),
                              ),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Conversation (interaction souhaitée)',
                                  s('conversation', orElse: '—')),
                              const SizedBox(height: 8),
                              lineIf(
                                showTemperatureLevel(),
                                'Température (préférence de climatisation)',
                                s('temperatureLevel', orElse: '—'),
                              ),
                              const SizedBox(height: 8),
                              lineIf(
                                showScentLevel(),
                                'Parfum / désodorisant',
                                s('scentLevel',
                                    orElse: perfumeOn ? 'Oui' : 'Non'),
                              ),
                              const SizedBox(height: 8),
                              lineIf(
                                !isMoto(),
                                'Lumière d’ambiance (couleur/intensité)',
                                s('ambientLight', orElse: '—'),
                              ),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Playlist exclusive (on/off)', musicOn),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Température réglée (on/off)', tempSwitchOn),

                              const Divider(color: Colors.white10, height: 26),

                              // 2) Confort physique & ergonomique
                              Row(
                                children: const [
                                  GoldIcon(Icons.event_seat_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Confort physique et ergonomique',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem(
                                  'Position du siège (avant / arrière)',
                                  s('seatPosition', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Réglage du siège (inclinaison)',
                                  s('seatIncline', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Chargeur / USB',
                                  s('chargerUsb', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Wi-Fi', wifiOn),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Eau / Boisson', s('water', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Snacks', s('snacks', orElse: '—')),

                              const Divider(color: Colors.white10, height: 26),

                              // 3) Environnement & hygiène
                              Row(
                                children: const [
                                  GoldIcon(Icons.eco_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Environnement et hygiène',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem(
                                  'Véhicule non-fumeur', smokeFreeOn),
                              const SizedBox(height: 8),
                              _preferenceItem('Véhicule désinfecté',
                                  b('disinfected', orElse: false)),
                              const SizedBox(height: 8),
                              _preferenceItem('Animaux acceptés', petsOn),
                              const SizedBox(height: 8),
                              _preferenceItem('Silence à bord',
                                  b('silentRide', orElse: false)),

                              const Divider(color: Colors.white10, height: 26),

                              // 4) Style de conduite
                              Row(
                                children: const [
                                  GoldIcon(Icons.speed_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Style de conduite',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem(
                                  'Conduite (douce / normale / dynamique)',
                                  s('drivingStyle', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Vitesse moyenne (équilibrée / rapide)',
                                  s('avgSpeed', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Suspension / type de véhicule (souple / sport)',
                                  s('suspension', orElse: '—')),

                              const Divider(color: Colors.white10, height: 26),

                              // 5) Esthétique & premium
                              Row(
                                children: const [
                                  GoldIcon(Icons.diamond_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Préférences esthétiques et premium',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem('Type de véhicule',
                                  s('vehicleType', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Couleur intérieure',
                                  s('interiorColor', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Marques préférées', listStr('brands')),
                              const SizedBox(height: 8),
                              _preferenceItem('Chauffeur attitré',
                                  b('preferredDriver', orElse: false)),

                              const Divider(color: Colors.white10, height: 26),

                              // 6) Spécifiques moto (uniquement si Moto)
                              if (isMoto()) ...[
                                const Text(
                                  '🏍️ Spécifiques moto',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    letterSpacing: .2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _preferenceItem('Type de casque',
                                    s('helmetType', orElse: '—')),
                                const SizedBox(height: 8),
                                _preferenceItem('Hygiène casque',
                                    s('helmetHygiene', orElse: '—')),
                                const SizedBox(height: 8),
                                _preferenceItem('Tenue / protections',
                                    s('protections', orElse: '—')),
                                const SizedBox(height: 8),
                                _preferenceItem('Vitesse de conduite (moto)',
                                    s('motoSpeed', orElse: '—')),
                                const SizedBox(height: 8),
                                _preferenceItem('Discussion en intercom',
                                    b('intercom', orElse: false)),
                                const Divider(
                                    color: Colors.white10, height: 26),
                              ],

                              // 7) Écologie & éthique
                              Row(
                                children: const [
                                  GoldIcon(Icons.public_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Préférences écologiques et éthiques',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem('Type d’énergie',
                                  s('energyType', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Compensation carbone',
                                  b('carbonOffset', orElse: false)),
                              const SizedBox(height: 8),
                              _preferenceItem('Silence moteur',
                                  b('engineSilence', orElse: false)),

                              const Divider(color: Colors.white10, height: 26),

                              // 8) Paiement & réservation
                              Row(
                                children: const [
                                  GoldIcon(Icons.credit_card_rounded,
                                      size: 16, glow: true),
                                  SizedBox(width: 6),
                                  GradientText(
                                    'Paiement et réservation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              _preferenceItem('Mode de paiement',
                                  s('paymentMode', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Facture', s('invoiceMethod', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem('Notifications',
                                  s('notifications', orElse: '—')),
                            ],
                          );
                        }),

                        const SizedBox(height: 32),

                        // —— Actions
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

  Widget _headerMetaBar(Map<String, dynamic> data) {
    DateTime? _ts(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    // === Calcul de l'âge ===
    final birth = _ts(data['birthdate']);
    int? age;
    if (birth != null) {
      final now = DateTime.now();
      var a = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) a--;
      if (a >= 0 && a < 120) age = a;
    }

    // === Membre depuis ===
    final created = _ts(data['createdAt']);
    String? membreDepuis;
    if (created != null) {
      membreDepuis =
          '${created.month.toString().padLeft(2, '0')}/${created.year}';
    }

    final chips = <Widget>[
      if (age != null) _goldChip(icon: Icons.cake_rounded, label: '$age ans'),
      if (membreDepuis != null)
        _goldChip(
            icon: Icons.event_available_rounded,
            label: 'Membre depuis $membreDepuis'),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: chips,
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
              // voile très sombre
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
              // blur (verre) — sigma réduit pour perf
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
            // anneau très fin
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
