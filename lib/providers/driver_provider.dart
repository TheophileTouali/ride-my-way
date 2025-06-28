import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  // ✅ AJOUTE CETTE MÉTHODE
  Future<void> initializeUser() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final doc = await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
  if (doc.exists) {
    _user = DriverUser.fromMap(doc.data()!, uid: uid); // ✅ maintenant valide
    notifyListeners();
  }
}

}
