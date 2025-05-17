import 'package:flutter/material.dart';

class UserProvider with ChangeNotifier {
  String? _userName;

  bool get isLoggedIn => _userName != null;

  String get userName => _userName ?? "Invité";

  void login(String name) {
    _userName = name;
    notifyListeners();
  }

  void logout() {
    _userName = null;
    notifyListeners();
  }
}
