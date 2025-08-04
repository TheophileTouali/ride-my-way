import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class PaymentCancelScreen extends StatelessWidget {
  const PaymentCancelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel, color: Colors.redAccent, size: 80),
            const SizedBox(height: 16),
            const Text(
              "Paiement annulé",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.go('/confirmation'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold),
              child: const Text("Réessayer", style: TextStyle(color: Colors.black)),
            )
          ],
        ),
      ),
    );
  }
}
