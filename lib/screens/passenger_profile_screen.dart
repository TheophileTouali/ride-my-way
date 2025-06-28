import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io';

import '../themes/app_theme.dart';
import '../providers/user_provider.dart';

class PassengerProfileScreen extends StatefulWidget {
  const PassengerProfileScreen({super.key});

  @override
  State<PassengerProfileScreen> createState() => _PassengerProfileScreenState();
}

class _PassengerProfileScreenState extends State<PassengerProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  String? imageUrl;

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      setState(() {
        userData = doc.data();
        imageUrl = doc['photoUrl'];
        isLoading = false;
      });
    }
  }

  Future<void> pickAndUploadImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos/${FirebaseAuth.instance.currentUser!.uid}.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({'photoUrl': url});

      setState(() => imageUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Photo de profil mise à jour")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = Provider.of<UserProvider>(context).preferences;

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
        title: const Text("Mon Profil",
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            )),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Animate(
              effects: [
                FadeEffect(duration: 500.ms),
                MoveEffect(begin: const Offset(0, 20), duration: 500.ms)
              ],
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: pickAndUploadImage,
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
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.grey.shade900,
                          backgroundImage: imageUrl != null
                              ? NetworkImage(imageUrl!)
                              : const AssetImage('assets/images/user_placeholder.png') as ImageProvider,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text("${userData?['firstName']} ${userData?['lastName']}",
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 4),
                    Text(userData?['email'] ?? '',
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.green.withOpacity(0.12),
                        border: Border.all(color: Colors.greenAccent),
                      ),
                      child: const Text("✅ Profil vérifié",
                          style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
                    ),

                        const SizedBox(height: 36),
                        Container(
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
                              const Text(
                                "📍 Informations personnelles",
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'PlayfairDisplay',
                                ),
                              ),
                              const SizedBox(height: 16),
                              _personalInfoLine(Icons.location_on, "Adresse", userData?['address'] ?? ''),
                              const Divider(color: Colors.white10, height: 28),
                              _personalInfoLine(Icons.cake, "Date de naissance", userData?['birthdate']?.toDate()?.toString().split(' ')[0] ?? ''),
                              const Divider(color: Colors.white10, height: 28),
                              _personalInfoLine(Icons.phone_android_rounded, "Téléphone", userData?['phone'] ?? ''),
                            ],
                          ),
                        ),

                          const SizedBox(height: 24),
                          Container(
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
                                const Text(
                                  "🎧 Vos préférences de trajet",
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'PlayfairDisplay',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _preferenceItem("Ambiance", prefs.ambiance),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Playlist exclusive", prefs.music),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Parfum d’ambiance", prefs.perfume),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Température réglée", prefs.temperature),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Wi-Fi premium", prefs.wifi),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Trajet non-fumeur", prefs.smokeFree),
                                const Divider(color: Colors.white10, height: 26),
                                _preferenceItem("Animaux élégants acceptés", prefs.pets),
                              ],
                            ),
                          ),
                              _sectionCard("", [
                              _reviewSlider(),
                            ]),
                            const SizedBox(height: 24),
                            _sectionCard("Réputation prestige", [
                              Row(
                                children: const [
                                  Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "Voyageur d'excellence",
                                    style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _infoRow("Note globale", "⭐ 4.9 / 5"),
                              _infoRow("Distinction", "Voyageur d'Or"),
                              _infoRow("Respect des trajets", "98 %"),
                              _infoRow("Chauffeurs satisfaits", "37 / 38"),
                            ]),

                   const SizedBox(height: 32),
                    Center(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 280,
                            child: ElevatedButton.icon(
                              onPressed: () => context.go('/edit-profile'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              ),
                              icon: const Icon(Icons.edit, size: 20),
                              label: const Text(
                                "Modifier mes informations",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 280,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push('/preferences-edit'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              ),
                              icon: const Icon(Icons.tune_rounded, size: 20),
                              label: const Text(
                                "Modifier mes préférences",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 280,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Provider.of<UserProvider>(context, listen: false).logout();
                                context.go('/login');
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              ),
                              icon: const Icon(Icons.logout, size: 20),
                              label: const Text(
                                "Se déconnecter",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                  ],
                ),
              ),
            ),
    );
  }

    Widget _reviewSlider() {
    final reviews = [
      {"stars": "⭐️⭐️⭐️⭐️⭐️", "comment": "Toujours ponctuel et agréable.", "author": "Jean-Marc • 12 mai"},
      {"stars": "⭐️⭐️⭐️⭐️", "comment": "Très respectueux et discret.", "author": "Fatou • 28 avril"},
      {"stars": "⭐️⭐️⭐️⭐️⭐️", "comment": "Une expérience parfaite à chaque fois.", "author": "Hugo • 5 avril"},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            "📝 Avis des chauffeurs",
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: PageView.builder(
            itemCount: reviews.length,
            controller: PageController(viewportFraction: 0.9),
            itemBuilder: (context, index) {
              final r = reviews[index];
              return _reviewCard(r['stars']!, r['comment']!, r['author']!);
            },
          ),
        ),
      ],
    );
  }

    Widget _reviewCard(String stars, String comment, String author) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stars, style: const TextStyle(color: Colors.amber, fontSize: 16)),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              comment,
              style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              author,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
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
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(
        flex: 6,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ],
  );
}

Widget _preferenceItem(String label, dynamic value) {
  final isBool = value is bool;
  final displayValue = isBool ? (value ? "Oui" : "Non") : value.toString();
  final valueColor = isBool
      ? (value ? AppColors.gold : Colors.white38)
      : AppColors.gold;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.check_rounded,
          size: 16,
          color: isBool && !value ? Colors.white24 : AppColors.deepGold),
      const SizedBox(width: 12),
      Expanded(
        flex: 5,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(
        flex: 5,
        child: Text(
          displayValue,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}



  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
            )),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(label, style: const TextStyle(color: Colors.white70))),
          Expanded(
              flex: 6,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
