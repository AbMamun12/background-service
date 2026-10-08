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

  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

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

    // Setup custom notification channels on Android
    if (Platform.isAndroid) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        if (requestPermission) {
          try {
            await androidImpl.requestNotificationsPermission();
            await androidImpl.requestExactAlarmsPermission();
          } catch (e) {
            debugPrint('[NotificationService] Notification permission request skipped/failed: $e');
          }
        }
        try {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              'deskfit_alerts_channel',
              'DeskFit Alerts',
              description: 'This channel is used for DeskFit tracking and standing break reminders.',
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              'deskfit_bg_channel',
              'DeskFit Active Tracking',
              description: 'This channel is used for DeskFit tracking notifications in foreground.',
              importance: Importance.low,
              playSound: false,
              enableVibration: false,
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

  /// Displays or updates the persistent foreground service notification (ID 888)
  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String content,
    int progress = 0,
    int maxProgress = 0,
    bool showProgress = false,
    String? payload,
  }) async {
    try {
      if (!_isInitialized) await initialize(requestPermission: false);

      final androidDetails = AndroidNotificationDetails(
        'deskfit_bg_channel',
        'DeskFit Active Tracking',
        channelDescription:
            'This channel is used for DeskFit tracking notifications in foreground.',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: showProgress,
        maxProgress: maxProgress,
        progress: progress,
        ongoing: true,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(
          presentAlert: false,
          presentSound: false,
        ),
      );

      await _plugin.show(
        id: id,
        title: title,
        body: content,
        notificationDetails: details,
        payload: payload ?? 'standing_overlay',
      );
    } catch (e) {
      debugPrint('[NotificationService] Error showing progress notification: $e');
    }
  }

  /// Show high-priority standing notification
  Future<void> showStandingAlertNotification({
    String title = '⏰ Time to Stand Up & Stretch!',
    String body = 'Break time reached. Tap to open standing overlay screen and stretch.',
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'deskfit_alerts_channel',
      'DeskFit Alerts',
      channelDescription: 'Critical reminders to stand up and break sedentary posture',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
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
      id: 202,
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'standing_overlay',
    );
  }

  Future<void> cancelStandingNotification() async {
    await _plugin.cancel(id: 202);
  }
}
