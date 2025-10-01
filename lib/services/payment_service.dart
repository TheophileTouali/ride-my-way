import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentService {
  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
       defaultTargetPlatform == TargetPlatform.iOS);

  /// Ouvre la PaymentSheet (mobile) ou Stripe Checkout (web).
  /// - En cas d'annulation, Stripe lève une `StripeException` avec `code == FailureCode.canceled`.
  /// - En cas d'erreur (clé/secret manquant, URL invalide, etc.), on lève une Exception.
  static Future<void> processPayment({
    required Map<String, dynamic> stripeResponse,
    ThemeMode themeMode = ThemeMode.dark,
    String merchantDisplayName = 'Ride My Way',
  }) async {
    if (_isMobile) {
      final clientSecret = stripeResponse['clientSecret'] as String?;
      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('Client secret Stripe manquant.');
      }

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: merchantDisplayName,
          allowsDelayedPaymentMethods: true,
          style: themeMode,
        ),
      );

      // ⚠️ Ne pas catcher ici : laisse remonter StripeException (canceled / failed)
      await Stripe.instance.presentPaymentSheet();
      return;
    }

    if (kIsWeb) {
      final checkoutUrl = stripeResponse['checkoutUrl'] as String?;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        throw Exception('URL Stripe Checkout manquante.');
      }

      final ok = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      );
      if (!ok) {
        throw Exception('Impossible d’ouvrir Stripe Checkout.');
      }
      return;
    }

    throw UnsupportedError('Plateforme non supportée.');
  }
}
