import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/standing_schedule.dart';
import 'notification_service.dart';

class AppBackgroundService {
  AppBackgroundService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static const String _schedulesKey = 'standing_schedules';

  /// Initialize background service configuration and sync alarms
  static Future<void> initialize() async {
    debugPrint('[BackgroundService] Configuring flutter_background_service...');

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'deskfit_bg_channel',
      'DeskFit Standing Service',
      description: 'Active standing alarm and break alert service',
      importance: Importance.max,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Do NOT start automatically on boot/app launch
        isForegroundMode: true,
        notificationChannelId: 'deskfit_bg_channel',
        initialNotificationTitle: '⏰ Time to Stand Up!',
        initialNotificationContent: 'Standing break in progress...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    debugPrint('[BackgroundService] Configuration ready. Syncing alarms...');
    await syncAllAlarms();
  }

  /// Synchronize all configured schedules with AlarmManager
  static Future<void> syncAllAlarms() async {
    if (!Platform.isAndroid) return;
    final schedules = await getSchedules();
    for (final schedule in schedules) {
      if (schedule.isEnabled) {
        await scheduleAlarm(schedule);
      } else {
        await cancelAlarm(schedule.id);
      }
    }
  }

  /// Schedule an exact alarm for a specific StandingSchedule
  static Future<void> scheduleAlarm(StandingSchedule schedule) async {
    if (!Platform.isAndroid) return;
    final int alarmId = schedule.id.hashCode & 0x7FFFFFFF;
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, schedule.hour, schedule.minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    debugPrint('[BackgroundService] Scheduling exact alarm for ${schedule.formattedTime} (ID: $alarmId at $target)');
    await AndroidAlarmManager.oneShotAt(
      target,
      alarmId,
      alarmTriggerCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  }

  /// Cancel an alarm by schedule ID
  static Future<void> cancelAlarm(String id) async {
    if (!Platform.isAndroid) return;
    final int alarmId = id.hashCode & 0x7FFFFFFF;
    debugPrint('[BackgroundService] Cancelling alarm ID: $alarmId');
    await AndroidAlarmManager.cancel(alarmId);
  }

  /// Retrieve all configured schedules
  static Future<List<StandingSchedule>> getSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_schedulesKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return raw
        .map((e) => StandingSchedule.fromJson(e))
        .toList()
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
  }

  /// Save all configured schedules and resync exact alarms
  static Future<void> saveSchedules(List<StandingSchedule> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = list.map((e) => e.toJson()).toList();
    await prefs.setStringList(_schedulesKey, raw);
    await syncAllAlarms();
  }

  /// Add a new schedule
  static Future<void> addSchedule(int hour, int minute) async {
    final list = await getSchedules();
    final newSchedule = StandingSchedule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      hour: hour,
      minute: minute,
      isEnabled: true,
    );
    list.add(newSchedule);
    await saveSchedules(list);
  }

  /// Delete a schedule by ID
  static Future<void> deleteSchedule(String id) async {
    await cancelAlarm(id);
    final list = await getSchedules();
    list.removeWhere((item) => item.id == id);
    await saveSchedules(list);
  }

  /// Toggle enabled status of a schedule
  static Future<void> toggleSchedule(String id, bool isEnabled) async {
    final list = await getSchedules();
    final index = list.indexWhere((item) => item.id == id);
    if (index != -1) {
      list[index] = list[index].copyWith(isEnabled: isEnabled);
      await saveSchedules(list);
    }
  }

  /// Start background service immediately (used on scheduled trigger)
  static Future<void> startService() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
    } else {
      _service.invoke('start_alarm_audio');
    }
  }

  /// Stop currently sounding alarm, cancel notifications, and turn off background service completely
  static Future<void> stopAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_alarm_triggered', false);

    _service.invoke('stop_alarm_audio');
    _service.invoke('stopService');

    await NotificationService.instance.cancelStandingNotification();
    await NotificationService.instance.cancelNotification(888);
  }

  /// Request background isolate to start alarm audio
  static void startAlarmAudio() {
    _service.invoke('start_alarm_audio');
  }

  /// Request background isolate to stop alarm audio
  static void stopAlarmAudio() {
    _service.invoke('stop_alarm_audio');
  }

  /// Stream of status updates from background isolate
  static Stream<Map<String, dynamic>?> get onStatusChange =>
      _service.on('status');
}

/// Top-level callback fired by AndroidAlarmManager at the exact scheduled time
@pragma('vm:entry-point')
void alarmTriggerCallback(int id) async {
  debugPrint('[AlarmManager Callback] Alarm triggered for schedule ID: $id');
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_alarm_triggered', true);

  // Automatically reschedule this specific schedule for tomorrow
  try {
    final rawList = prefs.getStringList(AppBackgroundService._schedulesKey) ?? [];
    final schedules = rawList.map((e) => StandingSchedule.fromJson(e)).toList();
    StandingSchedule? matchedSchedule;
    for (final s in schedules) {
      if ((s.id.hashCode & 0x7FFFFFFF) == id) {
        matchedSchedule = s;
        break;
      }
    }

    if (matchedSchedule != null && matchedSchedule.isEnabled) {
      final now = DateTime.now();
      var tomorrow = DateTime(now.year, now.month, now.day, matchedSchedule.hour, matchedSchedule.minute);
      if (!tomorrow.isAfter(now)) {
        tomorrow = tomorrow.add(const Duration(days: 1));
      }
      debugPrint('[AlarmManager Callback] Rescheduling for next cycle at: $tomorrow');
      await AndroidAlarmManager.oneShotAt(
        tomorrow,
        id,
        alarmTriggerCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }
  } catch (e) {
    debugPrint('[AlarmManager Callback] Error rescheduling next occurrence: $e');
  }

  // 1. Turn on background service so it runs foreground notification and audio in isolate
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  } else {
    service.invoke('start_alarm_audio');
  }

  // 2. Show high-priority heads-up notification with sound & vibration
  try {
    await NotificationService.instance.initialize(requestPermission: false);
    await NotificationService.instance.showStandingAlertNotification(
      title: '⏰ Time to Stand Up & Stretch!',
      body: 'Scheduled break reached. Tap to open standing overlay.',
    );
  } catch (e) {
    debugPrint('[AlarmManager Callback] Error displaying notification: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Entry point for Background Service Isolate (Runs ONLY while alarm is active)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  debugPrint('[BackgroundService Isolate] onStart launched at scheduled alarm time.');

  await NotificationService.instance.initialize(requestPermission: false);

  AudioPlayer? alarmPlayer;
  bool isAudioPlaying = false;

  Future<void> playLoopingAlarm() async {
    if (isAudioPlaying) return;
    try {
      alarmPlayer ??= AudioPlayer();
      await alarmPlayer?.setReleaseMode(ReleaseMode.loop);

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final soundPath = prefs.getString('alarm_sound') ?? 'audio/audio_1.wav';

      await alarmPlayer?.play(AssetSource(soundPath));
      isAudioPlaying = true;
      debugPrint('[BackgroundService Isolate] Alarm audio playing continuously: $soundPath');
      service.invoke('status', {
        'is_audio_playing': true,
        'is_triggered': true,
      });
    } catch (e) {
      debugPrint('[BackgroundService Isolate] Error playing alarm: $e');
    }
  }

  Future<void> stopLoopingAlarm() async {
    try {
      if (alarmPlayer != null) {
        await alarmPlayer?.stop();
        isAudioPlaying = false;
        debugPrint('[BackgroundService Isolate] Alarm audio stopped.');
      }
    } catch (e) {
      debugPrint('[BackgroundService Isolate] Error stopping alarm: $e');
    }
  }

  Timer? keepAliveTimer;

  Future<void> updateForegroundNotification() async {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: '⏰ Time to Stand Up!',
        content: 'Standing break is active. Tap to open and complete.',
      );
      await NotificationService.instance.showProgressNotification(
        id: 888,
        title: '⏰ Time to Stand Up!',
        content: 'Standing break in progress. Tap to open overlay.',
        showProgress: false,
        payload: 'standing_overlay',
      );
    }
  }

  // Show active alarm foreground notification immediately
  await updateForegroundNotification();

  // Periodically refresh pinned notification while alarm is active
  keepAliveTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
    await updateForegroundNotification();
  });

  // Automatically begin playing audio
  await playLoopingAlarm();

  // Listen for audio control commands
  service.on('start_alarm_audio').listen((event) async {
    await playLoopingAlarm();
  });

  service.on('stop_alarm_audio').listen((event) async {
    await stopLoopingAlarm();
  });

  // When completed/dismissed, completely terminate service
  service.on('stopService').listen((event) async {
    debugPrint('[BackgroundService Isolate] stopService received. Shutting down background service.');
    keepAliveTimer?.cancel();
    await stopLoopingAlarm();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_alarm_triggered', false);

    await NotificationService.instance.cancelStandingNotification();
    await NotificationService.instance.cancelNotification(888);

    service.invoke('status', {
      'is_audio_playing': false,
      'is_triggered': false,
    });

    service.stopSelf(); // Shuts down Android Foreground Service completely
  });
}
