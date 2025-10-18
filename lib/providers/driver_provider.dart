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

    final doc =
        await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
    if (doc.exists) {
      _user = DriverUser.fromMap(doc.data()!, uid: uid); // ✅ maintenant valide
      notifyListeners();
    }
  }

  Future<void> updateDriverDocument(String docKey, String url) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docRef = FirebaseFirestore.instance.collection('drivers').doc(uid);

    // 🔄 Mise à jour du champ spécifique dans "documents"
    await docRef.set({
      'documents': {
        docKey: url,
      }
    }, SetOptions(merge: true));

    // 🔁 Mise à jour en local du modèle utilisateur
    final updatedDocs = Map<String, dynamic>.from(_user?.documents ?? {});
    updatedDocs[docKey] = url;

    _user = DriverUser(
      uid: _user!.uid,
      firstName: _user!.firstName,
      lastName: _user!.lastName,
      email: _user!.email,
      phone: _user!.phone,
      photoUrl: _user!.photoUrl,
      address: _user!.address,
      birthdate: _user!.birthdate,
      vehicleType: _user!.vehicleType,
      vehicleBrand: _user!.vehicleBrand,
      vehicleModel: _user!.vehicleModel,
      vehicleYear: _user!.vehicleYear,
      licensePlate: _user!.licensePlate,
      driverLicenseNumber: _user!.driverLicenseNumber,
      vehiclePhotoUrl: _user!.vehiclePhotoUrl,
      documents: updatedDocs,
    );

    notifyListeners();
  }
}
