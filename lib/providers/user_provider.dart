import 'package:flutter/foundation.dart';

class UserProvider with ChangeNotifier {
  // Ex: Données utilisateur à exposer globalement
  String _name = "Invité";

  String get name => _name;

  void setName(String newName) {
    _name = newName;
    notifyListeners();
  }
}
