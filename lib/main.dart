// lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';

// Firebase core
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Router & providers
import 'config/app_routes.dart';
import 'providers/user_provider.dart';
import 'providers/driver_provider.dart';
import 'package:provider/provider.dart';

// Stripe (po garde comme avant)
import 'package:flutter_stripe/flutter_stripe.dart';

// ─────────────────────────────────────────────
// NOTIFS & FCM — entièrement NO-OP sur le Web
// ─────────────────────────────────────────────
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

final FlutterLocalNotificationsPlugin _flnp = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _nearbyChannel = AndroidNotificationChannel(
  'nearby_courses_channel',
  'Courses proches',
  description: 'Alertes de courses à proximité',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('urgent_alert'),
  enableVibration: true,
  showBadge: true,
);

Future<void> _initLocalNotifications() async {
  if (!_isMobile) return; // ← rien à faire sur le Web

  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
    requestBadgePermission: true,
  );
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  await _flnp.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (resp) async {
      // Exemple: AppRoutes.router.go('/driver-home?openNearbyDialog=1');
    },
  );

  final android = _flnp.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_nearbyChannel);
}

Future<void> _showNearbyHeadsUp({
  required String title,
  required String body,
}) async {
  if (!_isMobile) return; // ← pas de notif locale sur Web
  await _flnp.show(
    1001,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _nearbyChannel.id,
        _nearbyChannel.name,
        channelDescription: _nearbyChannel.description,
        priority: Priority.max,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('urgent_alert'),
        enableVibration: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      ),
    ),
    payload: 'open_nearby_dialog',
  );
}

// Doit être top-level; sera enregistré uniquement sur mobile.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!_isMobile) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final title = message.notification?.title ?? 'Course proche disponible';
  final body = message.notification?.body ??
      '${message.data['from'] ?? 'Départ'} ➜ ${message.data['to'] ?? 'Arrivée'}';

  await _initLocalNotifications();
  await _showNearbyHeadsUp(title: title, body: body);
}

Future<void> _saveDriverFcmToken() async {
  if (!_isMobile) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set(
    {'fcmToken': token, 'lastFcmUpdate': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
  );
}

Future<void> _initFcmMobileOnly() async {
  if (!_isMobile) {
    debugPrint('🔕 FCM ignoré sur le Web (pas de service worker configuré)');
    return;
  }

  await _initLocalNotifications();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final title = message.notification?.title ?? 'Course proche disponible';
    final body = message.notification?.body ??
        '${message.data['from'] ?? 'Départ'} ➜ ${message.data['to'] ?? 'Arrivée'}';
    await _showNearbyHeadsUp(title: title, body: body);
  });

  FirebaseMessaging.onMessageOpenedApp.listen((_) {
    // Exemple: AppRoutes.router.go('/driver-home?openNearbyDialog=1');
  });

  FirebaseAuth.instance.authStateChanges().listen((u) async {
    if (u != null) await _saveDriverFcmToken();
  });

  FirebaseMessaging.instance.onTokenRefresh
      .listen((_) => _saveDriverFcmToken());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Stripe
  if (!kIsWeb) {
    Stripe.publishableKey = const String.fromEnvironment(
      'STRIPE_PK',
      defaultValue:
          'pk_test_51Rp4UvRroJq1dBtwofYynv6pjMhTKEetwIKzYonPh46U1ND4fyFii0fL5NzfoJ7AOjvqoDPe5eV75qoQ5BrTvUnP00YaG7r56f',
    );
    if (Platform.isIOS) {
      Stripe.merchantIdentifier = 'merchant.com.example.ride_my_way';
    }
    Stripe.urlScheme = 'flutterstripe';
  }

  // 🔔 FCM/Notifs → seulement Android/iOS
  await _initFcmMobileOnly();

  runApp(const RideMyWayApp());
}

class RideMyWayApp extends StatelessWidget {
  const RideMyWayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
            create: (_) => DriverProvider()..initializeUser()),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Ride My Way',
        theme: ThemeData(
          fontFamily: 'PlayfairDisplay',
          scaffoldBackgroundColor: Colors.black,
        ),
        routerConfig: AppRoutes.router,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('fr', 'FR'),
          Locale('en', 'US'),
        ],
      ),
    );
  }
}
