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

  Widget _actionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.30),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.settings, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                'Actions du compte',
                style: TextStyle(
                  color: AppColors.gold,
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
            gradient: const LinearGradient(
              colors: [AppColors.gold, AppColors.deepGold],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.black, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
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
        splashColor: Colors.redAccent.withOpacity(.15),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: Colors.redAccent.withOpacity(.8), width: 1.4),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.redAccent, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.redAccent,
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

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/home'),
        ),
        centerTitle: true,
        title: const Text(
          'Mon Profil',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
      ),

      /// 🔥 Lecture *en temps réel* du document utilisateur
      body: uid == null
          ? const Center(
              child:
                  Text('Non connecté', style: TextStyle(color: Colors.white70)))
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
                        // —— Avatar
                        GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: Container(
                            padding: const EdgeInsets.all(4),
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
                            child: ClipOval(
                              child: SizedBox(
                                width: 104,
                                height: 104,
                                child: bust == null
                                    ? Image.asset(
                                        'assets/images/user_placeholder.png',
                                        fit: BoxFit.cover,
                                      )
                                    : Image.network(
                                        bust,
                                        key: ValueKey(
                                            bust), // force le rebuild si URL change
                                        gaplessPlayback:
                                            true, // évite le flash au remplacement
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, st) {
                                          debugPrint(
                                              '⚠️ Avatar load error: $err');
                                          return Image.asset(
                                            'assets/images/user_placeholder.png',
                                            fit: BoxFit.cover,
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // —— Identité
                        Text(
                          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(data['email'] ?? '',
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.green.withOpacity(0.12),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: const Text('✅ Profil vérifié',
                              style: TextStyle(
                                  color: Colors.greenAccent, fontSize: 13)),
                        ),

                        const SizedBox(height: 36),

                        // —— Infos personnelles
                        _sectionCard(
                          title: '📍 Informations personnelles',
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

                        // —— Préférences (NOUVELLE VERSION – étendue & rétro-compatible)
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
                            title: '🎧 Vos préférences de trajet',
                            children: [
                              // 1) Ambiance & confort intérieur
                              Text(
                                '🚗 Ambiance et confort intérieur',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Ambiance sonore (niveau de musique)',
                                  ambiance),
                              const SizedBox(height: 8),
                              lineIf(
                                  showMusicStyle(),
                                  'Style musical (genre favori)',
                                  s('musicStyle', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Conversation (interaction souhaitée)',
                                  s('conversation', orElse: '—')),
                              const SizedBox(height: 8),
                              lineIf(
                                  showTemperatureLevel(),
                                  'Température (préférence de climatisation)',
                                  s('temperatureLevel', orElse: '—')),
                              const SizedBox(height: 8),
                              lineIf(
                                  showScentLevel(),
                                  'Parfum / désodorisant',
                                  s('scentLevel',
                                      orElse: perfumeOn ? 'Oui' : 'Non')),
                              const SizedBox(height: 8),
                              lineIf(
                                  !isMoto(),
                                  'Lumière d’ambiance (couleur/intensité)',
                                  s('ambientLight', orElse: '—')),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Playlist exclusive (on/off)', musicOn),
                              const SizedBox(height: 8),
                              _preferenceItem(
                                  'Température réglée (on/off)', tempSwitchOn),

                              const Divider(color: Colors.white10, height: 26),

                              // 2) Confort physique & ergonomique
                              Text(
                                '🪑 Confort physique et ergonomique',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                              Text(
                                '🚭 Environnement et hygiène',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                              Text(
                                '🏎️ Style de conduite',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                              Text(
                                '🧥 Préférences esthétiques et premium',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                                Text(
                                  '🏍️ Spécifiques moto',
                                  style: const TextStyle(
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
                              Text(
                                '🌍 Préférences écologiques et éthiques',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                              Text(
                                '💳 Paiement et réservation',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: .2,
                                ),
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
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _actionsCard(context),
                            const SizedBox(height: 32),
                          ],
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ——— UI helpers
  Widget _sectionCard({required String title, required List<Widget> children}) {
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }

  Widget _personalInfoLine(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white60, size: 18),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          flex: 6,
          child: Text(value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ),
      ],
    );
  }

  Widget _preferenceItem(String label, dynamic value) {
    final isBool = value is bool;
    final displayValue = isBool ? (value ? 'Oui' : 'Non') : value.toString();
    final valueColor =
        isBool ? (value ? AppColors.gold : Colors.white38) : AppColors.gold;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_rounded,
            size: 16,
            color: isBool && !value ? Colors.white24 : AppColors.deepGold),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          flex: 5,
          child: Text(
            displayValue,
            textAlign: TextAlign.right,
            style: TextStyle(
                color: valueColor, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
