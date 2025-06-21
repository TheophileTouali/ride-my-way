import 'package:flutter/material.dart';
import '../models/driver_user.dart';

class DriverProvider with ChangeNotifier {
  DriverUser? _user;

  DriverUser? get user => _user;

  void setUser(DriverUser user) {
    _user = user;
    notifyListeners();
  }

  void logout() {
    _user = null;
    notifyListeners();
  }
}
