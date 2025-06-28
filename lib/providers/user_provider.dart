import 'package:flutter/material.dart';
import '../models/passenger_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class UserProvider with ChangeNotifier {
  String? _userName;
  String? _email;
  String? _avatarUrl; // ✅ Champ pour l'URL de la photo

  bool get isLoggedIn => _userName != null;

  String get userName => _userName ?? "Invité";
  String get userEmail => _email ?? "inconnu@exemple.com";
  String? get avatarUrl => _avatarUrl; // ✅ Getter exposé

  /// ✅ Connexion de l'utilisateur
  void login(String name, String email, {String? avatarUrl}) {
    _userName = name;
    _email = email;
    _avatarUrl = avatarUrl;
    notifyListeners();
  }

  /// ✅ Déconnexion
  void logout() {
    _userName = null;
    _email = null;
    _avatarUrl = null;
    notifyListeners();
  }

  // ✅ === GESTION DES PRÉFÉRENCES PASSAGER ===
  PassengerPreferences _preferences = PassengerPreferences(
    ambiance: 'Calme & relax',
    music: false,
    perfume: false,
    temperature: false,
    wifi: false,
    smokeFree: false,
    pets: false,
  );

  PassengerPreferences get preferences => _preferences;

  void updatePreferences(PassengerPreferences prefs) async {
    _preferences = prefs;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'preferences': {
          'ambiance': prefs.ambiance,
          'music': prefs.music,
          'perfume': prefs.perfume,
          'temperature': prefs.temperature,
          'wifi': prefs.wifi,
          'smokeFree': prefs.smokeFree,
          'pets': prefs.pets,
        }
      });
    }
  }

  Future<void> loadUserData() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();

    if (data != null && data['preferences'] != null) {
      final p = data['preferences'];
      _preferences = PassengerPreferences(
        ambiance: p['ambiance'] ?? 'Calme & relax',
        music: p['music'] ?? false,
        perfume: p['perfume'] ?? false,
        temperature: p['temperature'] ?? false,
        wifi: p['wifi'] ?? false,
        smokeFree: p['smokeFree'] ?? false,
        pets: p['pets'] ?? false,
      );
      notifyListeners();
    }
  }
}


}

