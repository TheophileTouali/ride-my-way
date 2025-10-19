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

      // On récupère l’ancienne URL depuis Firestore pour pouvoir supprimer l’ancien fichier
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final String? oldUrl = userDoc.data()?['photoUrl'] as String?;

      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = 'users_data/${user.uid}/profile_$ts.png';
      final ref = storage.ref().child(path);

      // Upload selon plateforme
      UploadTask task;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        task = ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      } else {
        task = ref.putFile(
            File(picked.path), SettableMetadata(contentType: 'image/png'));
      }
      await task.whenComplete(() {});

      // URL publique signée
      final newUrl = (await ref.getDownloadURL()).trim();

      // Firestore + FirebaseAuth (photoURL)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': newUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.updatePhotoURL(newUrl);

      // Supprimer l’ancienne image (best effort)
      if (oldUrl != null && oldUrl.isNotEmpty) {
        try {
          await storage.refFromURL(oldUrl).delete();
        } catch (e) {
          debugPrint('ℹ️ Ancienne photo non supprimée: $e');
        }
      }

      // Feedback
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
    final prefs = Provider.of<UserProvider>(context).preferences;
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
                final photo = (data['photoUrl'] as String?) ?? '';
                final bust = photo.isEmpty ? null : _cacheBust(photo);

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
                                        key: ValueKey(bust),
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

                        // —— Préférences
                        Builder(builder: (_) {
                          final prefs =
                              Provider.of<UserProvider>(context).preferences;
                          return _sectionCard(
                            title: '🎧 Vos préférences de trajet',
                            children: [
                              _preferenceItem('Ambiance', prefs.ambiance),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem(
                                  'Playlist exclusive', prefs.music),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem(
                                  'Parfum d’ambiance', prefs.perfume),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem(
                                  'Température réglée', prefs.temperature),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem('Wi-Fi premium', prefs.wifi),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem(
                                  'Trajet non-fumeur', prefs.smokeFree),
                              const Divider(color: Colors.white10, height: 26),
                              _preferenceItem(
                                  'Animaux élégants acceptés', prefs.pets),
                            ],
                          );
                        }),

                        const SizedBox(height: 32),

                        // —— Actions
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
