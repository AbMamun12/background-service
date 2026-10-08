import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Callback when notification is clicked
  static void Function(String? payload)? onNotificationClick;

  Future<void> initialize({bool requestPermission = true}) async {
    if (_isInitialized) return;

    // Timezone setup
    try {
      tz.initializeTimeZones();
      final String timeZoneName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('[NotificationService] Timezone init fallback: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('[NotificationService] Notification tapped payload: ${response.payload}');
        if (onNotificationClick != null) {
          onNotificationClick!(response.payload);
        }
      },
    );

    // Request permissions on Android 13+ and setup channel
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        if (requestPermission) {
          try {
            await androidImpl.requestNotificationsPermission();
          } catch (e) {
            debugPrint('[NotificationService] Notification permission request skipped/failed: $e');
          }
        }
        try {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              'deskfit_standing_alerts',
              'Standing & Posture Alerts',
              description: 'Critical reminders to stand up and break sedentary posture',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
        } catch (e) {
          debugPrint('[NotificationService] Channel creation failed: $e');
        }
      }
    }

    _isInitialized = true;
    debugPrint('[NotificationService] Initialized successfully.');
  }

  /// Show high-priority standing notification
  Future<void> showStandingAlertNotification({
    String title = '⏰ Time to Stand Up & Stretch!',
    String body = 'Break time reached. Tap to open standing overlay screen and stretch.',
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'deskfit_standing_alerts',
      'Standing & Posture Alerts',
      channelDescription: 'Critical reminders to stand up and break sedentary posture',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ticker: 'Standing Reminder',
      playSound: true,
      enableVibration: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      id: 999,
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'standing_overlay',
    );
  }

  Future<void> cancelStandingNotification() async {
    await _plugin.cancel(id: 999);
  }
}
