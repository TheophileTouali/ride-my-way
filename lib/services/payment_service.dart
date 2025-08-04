import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentService {
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<bool> processPayment({
    required Map<String, dynamic> stripeResponse,
  }) async {
    try {
      if (isMobile && stripeResponse['clientSecret'] != null) {
        await Stripe.instance.initPaymentSheet(
          paymentSheetParameters: SetupPaymentSheetParameters(
            paymentIntentClientSecret: stripeResponse['clientSecret'],
            merchantDisplayName: 'Ride My Way',
            style: ThemeMode.dark,
          ),
        );
        await Stripe.instance.presentPaymentSheet();
        return true;
      } else if (kIsWeb && stripeResponse['checkoutUrl'] != null) {
        final url = stripeResponse['checkoutUrl'];
        if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_self')) {
          throw Exception('Impossible d’ouvrir la page de paiement.');
        }
        return true;
      } else {
        throw UnsupportedError("Paiement non implémenté pour cette plateforme.");
      }
    } on StripeException catch (e) {
      debugPrint('Erreur paiement Stripe: ${e.error.localizedMessage}');
      return false;
    } catch (e) {
      debugPrint('Erreur inattendue paiement: $e');
      return false;
    }
  }
}
