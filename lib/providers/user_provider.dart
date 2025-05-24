import 'package:flutter/material.dart';

class UserProvider with ChangeNotifier {
  String? _userName;
  String? _email; // ✅ Ajout de l'attribut email

  bool get isLoggedIn => _userName != null;

  String get userName => _userName ?? "Invité";
  String get userEmail => _email ?? "inconnu@exemple.com"; // ✅ Getter email sécurisé

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
}
