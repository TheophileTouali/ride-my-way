import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animate_do/animate_do.dart';
import '../themes/app_theme.dart';

class BookingSuccessScreen extends StatefulWidget {
  const BookingSuccessScreen({super.key});

  @override
  State<BookingSuccessScreen> createState() => _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends State<BookingSuccessScreen> {
  late final String reservationId;

  @override
  void initState() {
    super.initState();
    reservationId = GoRouterState.of(context).uri.queryParameters['reservationId']!;
    Timer(const Duration(seconds: 3), () {
      context.go('/searching?reservationId=$reservationId');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: FadeIn(
          duration: const Duration(milliseconds: 800),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BounceInDown(
                duration: const Duration(milliseconds: 1200),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 4,
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.gold,
                    size: 100,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "Réservation Confirmée",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Merci pour votre confiance.\nVotre trajet est bien enregistré.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
