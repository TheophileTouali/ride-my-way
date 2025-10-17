import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PassengerReputation {
  final double averageRating;
  final int satisfiedDrivers;
  final int totalDrivers;
  final double tripRespectPercent;

  PassengerReputation({
    required this.averageRating,
    required this.satisfiedDrivers,
    required this.totalDrivers,
    required this.tripRespectPercent,
  });
}

Future<PassengerReputation> fetchPassengerReputation() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return PassengerReputation(
      averageRating: 0,
      satisfiedDrivers: 0,
      totalDrivers: 0,
      tripRespectPercent: 0,
    );
  }

  // 1️⃣ Avis reçus par le passager
  final feedbacksSnap = await FirebaseFirestore.instance
      .collection('feedbacks')
      .where('passengerId', isEqualTo: uid)
      .where('fromDriver', isEqualTo: true)
      .get();

  final feedbacks = feedbacksSnap.docs.map((d) => d.data()).toList();
  final totalFeedbacks = feedbacks.length;
  final double sum = feedbacks.fold<double>(
    0,
    (prev, f) => prev + ((f['rating'] ?? 0) as num).toDouble(),
  );
  final double avg = totalFeedbacks == 0 ? 0 : (sum / totalFeedbacks);
  final int satisfied =
      feedbacks.where((f) => ((f['rating'] ?? 0) as num) >= 4).length;

  // 2️⃣ Respect des trajets
  // On considère un trajet "respecté" s’il est "Terminée"
  // et "non annulé par le passager".
  final reservationsSnap = await FirebaseFirestore.instance
      .collection('reservations')
      .where('userId', isEqualTo: uid)
      .get();

  int totalTrips = 0;
  int respectedTrips = 0;

  for (final doc in reservationsSnap.docs) {
    final data = doc.data();
    final status =
        (data['status'] ?? '').toString(); // ex: "Terminée", "Annulée"
    final cancelledBy =
        (data['cancelledBy'] ?? '').toString(); // ex: "passenger"

    if (status.isNotEmpty) totalTrips++;

    if (status == 'Terminée') {
      respectedTrips++;
    } else if (status == 'Annulée' && cancelledBy == 'passenger') {
      // non respecté
    }
  }

  final double respectPct =
      totalTrips == 0 ? 0 : (respectedTrips / totalTrips) * 100;

  return PassengerReputation(
    averageRating: avg,
    satisfiedDrivers: satisfied,
    totalDrivers: totalFeedbacks,
    tripRespectPercent: respectPct,
  );
}
