import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'firebase_options.dart';
import 'config/app_routes.dart';
import 'providers/user_provider.dart';
import 'providers/driver_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Stripe : initialiser UNIQUEMENT sur Android/iOS (sur Web on passe par Checkout)
  if (!kIsWeb) {
    try {
      // ⚠️ Mets ta publishable key (même environnement que ta secret côté Functions)
      // Pro-tip: passe-la via --dart-define=STRIPE_PK=pk_test_xxx en CI/dev
      Stripe.publishableKey = const String.fromEnvironment(
        'STRIPE_PK',
        defaultValue: 'pk_test_51Rp4UvRroJq1dBtwofYynv6pjMhTKEetwIKzYonPh46U1ND4fyFii0fL5NzfoJ7AOjvqoDPe5eV75qoQ5BrTvUnP00YaG7r56f', // <-- remplace
      );

      // (Optionnel) Apple Pay
      Stripe.merchantIdentifier = 'merchant.com.example.ride_my_way';

      // ✅ Schéma de retour pour 3DS/banque (doit matcher le Manifest/Info.plist)
      Stripe.urlScheme = 'flutterstripe';

      await Stripe.instance.applySettings();
    } catch (e, st) {
      // On ne bloque pas le boot de l'app ; on loggue
      // (si cette init échoue, la PaymentSheet échouera ensuite)
      // Tu verras le message exact en console.
      // ignore: avoid_print
      print('⚠️ Stripe init failed: $e\n$st');
    }
  }

  runApp(const RideMyWayApp());
}

class RideMyWayApp extends StatelessWidget {
  const RideMyWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => DriverProvider()..initializeUser()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Ride My Way',
        theme: ThemeData(
          fontFamily: 'PlayfairDisplay',
          scaffoldBackgroundColor: Colors.black,
        ),
        routerConfig: AppRoutes.router,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      ),
    );
  }
}
