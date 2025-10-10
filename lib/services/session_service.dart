import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionService {
  static Future<void> markDriverLoggedOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(uid).update({
        'isLoggedIn': false,
        'lastActive': Timestamp.now(),
      });
    } catch (_) {}
  }
}
