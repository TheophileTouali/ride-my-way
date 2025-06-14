import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'config/app_routes.dart'; // ✅ important

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => UserProvider(),
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
      routerConfig: AppRoutes.router, // ✅ utilise le router central
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
