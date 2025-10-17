import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  late AndroidNotificationChannel _channel;

  Future<void> init({required SelectNotificationCallback onSelect}) async {
    // iOS init
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Android init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings,
        onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload != null) onSelect(payload);
    });

    // Canal Android haute importance avec son custom
    _channel = const AndroidNotificationChannel(
      'nearby_courses_channel',
      'Courses proches',
      description: 'Alertes de courses à proximité',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('urgent_alert'),
      enableVibration: true,
      showBadge: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  Future<void> showNearbyCourse({
    required String title,
    required String body,
    String payload = 'open_nearby_dialog',
    bool ongoing = false,
  }) async {
    final android = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      priority: Priority.max,
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent_alert'),
      enableVibration: true,
      category: AndroidNotificationCategory.call, // heads-up agressif
      fullScreenIntent: false, // passe à true si tu veux plein écran
      ticker: 'Course proche',
      visibility: NotificationVisibility.public,
      styleInformation: const DefaultStyleInformation(true, true),
      ongoing: ongoing,
      autoCancel: !ongoing,
    );

    final ios = const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
      // Pour un volume très fort, iOS « critical » nécessite une entitlement,
      // sinon on reste sur une alerte normale.
    );

    await _plugin.show(
      1001, // id fixe pour remplacer la précédente
      title,
      body,
      NotificationDetails(android: android, iOS: ios),
      payload: payload,
    );
  }

  Future<void> cancelNearby() async => _plugin.cancel(1001);
}
