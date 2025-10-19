// lib/providers/user_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/passenger_preferences.dart';

class UserProvider with ChangeNotifier {
  String? _userName;
  String? _email;
  String? _avatarUrl;

  // État login de base
  bool get isLoggedIn => _userName != null;
  String get userName => _userName ?? 'Invité';
  String get userEmail => _email ?? 'inconnu@exemple.com';
  String? get avatarUrl => _avatarUrl;

  // ===================== Session =====================

  void login(String name, String email, {String? avatarUrl}) {
    _userName = name;
    _email = email;
    _avatarUrl = avatarUrl;
    notifyListeners();
  }

  void logout() {
    _userName = null;
    _email = null;
    _avatarUrl = null;

    // (facultatif) réinitialise des préférences sûres
    _preferences = PassengerPreferences(
      ambiance: 'Silencieux',
      music: false,
      perfume: false,
      temperature: false,
      wifi: false,
      smokeFree: false,
      pets: false,
    );
    notifyListeners();
  }

  Future<void> updateAvatarUrl(String? url) async {
    _avatarUrl = url;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'photoUrl': url, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
  }

  // ===================== Préférences =====================

  PassengerPreferences _preferences = PassengerPreferences(
    ambiance: 'Silencieux',
    music: false,
    perfume: false,
    temperature: false,
    wifi: false,
    smokeFree: false,
    pets: false,
  );

  PassengerPreferences get preferences => _preferences;

  /// Persiste TOUTES les préférences dans Firestore (users/{uid}.preferences)
  /// + duplique 7 champs legacy à la racine pour compat.
  Future<void> updatePreferences(PassengerPreferences prefs) async {
    _preferences = prefs;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final map = prefs.toMap();

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'preferences': map,
      'updatedAt': FieldValue.serverTimestamp(),

      // ---- Compat descendante (anciens écrans) ----
      'ambiance': prefs.ambiance,
      'music': prefs.music,
      'perfume': prefs.perfume,
      'temperature': prefs.temperature,
      'wifi': prefs.wifi,
      'smokeFree': prefs.smokeFree,
      'pets': prefs.pets,
    }, SetOptions(merge: true));
  }

  /// Charge le document utilisateur et fusionne ancien/nouveau schéma.
  Future<void> loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};

    // Champs de profil basiques
    _userName = (data['firstName'] != null || data['lastName'] != null)
        ? '${(data['firstName'] ?? '').toString().trim()} ${(data['lastName'] ?? '').toString().trim()}'
            .trim()
        : _userName;
    _email = data['email']?.toString() ?? _email;
    _avatarUrl = data['photoUrl']?.toString() ?? _avatarUrl;

    // Nouveau schéma (sûr même si Firestore renvoie <dynamic, dynamic>)
    final dynamic prefsRaw = data['preferences'];
    final Map<String, dynamic> prefsMap = (prefsRaw is Map)
        ? Map<String, dynamic>.from(prefsRaw as Map)
        : <String, dynamic>{};

    // Fusionne avec les anciens champs à la racine
    final merged = <String, dynamic>{
      // legacy simples
      'ambiance': data['ambiance'],
      'music': data['music'],
      'perfume': data['perfume'],
      'temperature': data['temperature'],
      'wifi': data['wifi'],
      'smokeFree': data['smokeFree'],
      'pets': data['pets'],
      // puis les nouveaux (qui priment)
      ...prefsMap,
    };

    // Valeur par défaut sûre pour le Dropdown
    merged['ambiance'] ??= 'Silencieux';

    _preferences = PassengerPreferences.fromMap(merged);
    notifyListeners();
  }
}
