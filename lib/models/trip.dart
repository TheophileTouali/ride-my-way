import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final String id;
  final String from;
  final String to;
  final String status;
  final DateTime departureTime;
  final double price;

  Trip({
    required this.id,
    required this.from,
    required this.to,
    required this.status,
    required this.departureTime,
    required this.price,
  });

  factory Trip.fromMap(String id, Map<String, dynamic> map) {
    return Trip(
      id: id,
      from: map['from'] ?? '',
      to: map['to'] ?? '',
      status: map['status'] ?? '',
      departureTime: (map['timestamp'] as Timestamp).toDate(), // ✅ ici on corrige
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'from': from,
      'to': to,
      'status': status,
      'timestamp': Timestamp.fromDate(departureTime),
      'price': price,
    };
  }
}
