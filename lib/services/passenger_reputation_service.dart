import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PassengerReputation {
  final double avg;
  final int satisfied; // ≥ 4 étoiles
  final int total;
  final List<Map<String, dynamic>> reviews; // {rating, comment, timestamp}

  PassengerReputation({
    required this.avg,
    required this.satisfied,
    required this.total,
    required this.reviews,
  });
}

Future<PassengerReputation> fetchPassengerReputation({String? uid}) async {
  final _uid = uid ?? FirebaseAuth.instance.currentUser?.uid;
  if (_uid == null) {
    return PassengerReputation(avg: 0, satisfied: 0, total: 0, reviews: []);
  }

  final snap = await FirebaseFirestore.instance
      .collection('feedbacks')
      .where('passengerId', isEqualTo: _uid)
      .where('fromDriver', isEqualTo: true)
      .orderBy('timestamp', descending: true)
      .get();

  final reviews = snap.docs.map((d) => d.data()).toList();
  final total = reviews.length;
  final sum = reviews.fold<double>(
      0, (s, r) => s + ((r['rating'] ?? 0) as num).toDouble());
  final avg = total == 0 ? 0 : sum / total;
  final satisfied =
      reviews.where((r) => ((r['rating'] ?? 0) as num) >= 4).length;

  return PassengerReputation(
    avg: avg,
    satisfied: satisfied,
    total: total,
    reviews: reviews,
  );
}
