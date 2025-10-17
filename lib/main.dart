import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

// 🔔 Notifications & FCM
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Ton router & options
import 'firebase_options.dart';
import 'config/app_routes.dart';
import 'providers/user_provider.dart';
import 'providers/driver_provider.dart';

// ────────────────────────────────────────────────────────────────────────────
// Notifications locales (service minimal ici pour garder ton fichier autonome)
// Si tu as déjà NotificationService dans /services, importe-le plutôt.
// ────────────────────────────────────────────────────────────────────────────
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  // iOS
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestSoundPermission: true,
    requestBadgePermission: true,
  );

  // Android
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  await _flnp.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (resp) async {
      // 👉 Ici tu peux ouvrir directement ton écran ou ton dialogue
      // ex: AppRoutes.router.go('/driver-home?openNearbyDialog=1');
    },
  );

  // Canal Android
  final android = _flnp.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_nearbyChannel);
}

Future<void> _showNearbyHeadsUp({
  required String title,
  required String body,
}) async {
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
        category: AndroidNotificationCategory.call, // heads-up agressif
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

// ────────────────────────────────────────────────────────────────────────────
// FCM background handler (obligatoirement top-level)
// Affiche une notif locale quand un push arrive écran éteint / app en BG.
// ────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Important : init Firebase dans le handler BG
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final title = message.notification?.title ?? 'Course proche disponible';
  final body = message.notification?.body ??
      '${message.data['from'] ?? 'Départ'} ➜ ${message.data['to'] ?? 'Arrivée'}';

  // Initialise le plugin local si besoin (no-op si déjà fait)
  await _initLocalNotifications();
  await _showNearbyHeadsUp(title: title, body: body);
}

// ────────────────────────────────────────────────────────────────────────────
// Enregistrement du token FCM dans drivers/{uid}.fcmToken
// Appelé au démarrage et à chaque refresh de token.
// ────────────────────────────────────────────────────────────────────────────
Future<void> _saveDriverFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set(
    {'fcmToken': token, 'lastFcmUpdate': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Stripe (inchangé)
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Stripe.instance.applySettings();
      } catch (e, st) {
        // ignore: avoid_print
        print('⚠️ Stripe applySettings post-frame failed: $e\n$st');
      }
    });
  }

  // 🔔 Notifications locales + FCM
  await _initLocalNotifications();

  // Enregistre le handler background FCM
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Permissions de notifications (iOS + Android 13+)
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );
  // print('FCM permission: ${settings.authorizationStatus}');

  // Foreground messages → on affiche une notif locale heads-up
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final title = message.notification?.title ?? 'Course proche disponible';
    final body = message.notification?.body ??
        '${message.data['from'] ?? 'Départ'} ➜ ${message.data['to'] ?? 'Arrivée'}';
    await _showNearbyHeadsUp(title: title, body: body);
  });

  // Tap sur la notif quand l’app est en background → ici tu peux router
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    // Ex: AppRoutes.router.go('/driver-home?openNearbyDialog=1');
  });

  // Sauvegarde le token FCM quand l’utilisateur est connecté
  FirebaseAuth.instance.authStateChanges().listen((u) async {
    if (u != null) await _saveDriverFcmToken();
  });
  // Et quand le token refresh
  FirebaseMessaging.instance.onTokenRefresh
      .listen((_) => _saveDriverFcmToken());

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
