import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // ✅ Ajout
import 'firebase_options.dart';
import 'config/app_routes.dart';
import 'providers/user_provider.dart';
import 'providers/driver_provider.dart'; // ✅ conducteur
import 'package:flutter_stripe/flutter_stripe.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Configuration Stripe uniquement sur mobile
  if (!kIsWeb) {
    Stripe.publishableKey =
        "pk_test_51Rp4UvRroJq1dBtwofYynv6pjMhTKEetwIKzYonPh46U1ND4fyFii0fL5NzfoJ7AOjvqoDPe5eV75qoQ5BrTvUnP00YaG7r56f";
    await Stripe.instance.applySettings();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) => DriverProvider()..initializeUser(),
        ),
      ],
      child: const RideMyWayApp(),
    ),
  );
}

class RideMyWayApp extends StatelessWidget {
  const RideMyWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
    );
  }
}
