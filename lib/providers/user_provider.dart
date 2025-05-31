import 'package:flutter/material.dart';
import '../models/passenger_preferences.dart'; // <- Assure-toi que le modèle est bien importé

class UserProvider with ChangeNotifier {
  String? _userName;
  String? _email;

  bool get isLoggedIn => _userName != null;

  String get userName => _userName ?? "Invité";
  String get userEmail => _email ?? "inconnu@exemple.com";

  void login(String name, String email) {
    _userName = name;
    _email = email;
    notifyListeners();
  }

  void logout() {
    _userName = null;
    _email = null;
    notifyListeners();
  }

  // ✅ === GESTION DES PRÉFÉRENCES ===
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

  void updatePreferences(PassengerPreferences prefs) {
    _preferences = prefs;
    notifyListeners();
  }
}
