import 'package:flutter/material.dart';

class LiveTrackingScreen extends StatelessWidget {
  final String reservationId;

  const LiveTrackingScreen({super.key, required this.reservationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Suivi en direct")),
      body: Center(
        child: Text("Trajet en cours : $reservationId"),
      ),
    );
  }
}
