import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/standing_schedule.dart';
import 'notification_service.dart';

class AppBackgroundService {
  AppBackgroundService._();

  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static const String _schedulesKey = 'standing_schedules';

  /// Initialize background service configuration
  static Future<void> initialize() async {
    debugPrint('[BackgroundService] Configuring flutter_background_service...');

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'deskfit_bg_channel',
      'DeskFit Standing Service',
      description: 'Maintains scheduled timers and standing alarms in the background',
      importance: Importance.low,
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
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'deskfit_bg_channel',
        initialNotificationTitle: 'DeskFit Standing Monitor',
        initialNotificationContent: 'Monitoring scheduled standing times...',
        foregroundServiceNotificationId: 777,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    debugPrint('[BackgroundService] Configuration ready.');
  }

  /// Ensure background service is running
  static Future<void> ensureRunning() async {
    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
    }
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

  /// Save all configured schedules
  static Future<void> saveSchedules(List<StandingSchedule> list) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = list.map((e) => e.toJson()).toList();
    await prefs.setStringList(_schedulesKey, raw);
    _service.invoke('reload_schedules');
    await ensureRunning();
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

  /// Stop currently sounding alarm and dismiss alert until next scheduled time
  static Future<void> stopAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_alarm_triggered', false);
    _service.invoke('stop_alarm_audio');
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

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Entry point for Background Service Isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  debugPrint('[BackgroundService Isolate] onStart launched.');

  // Safe initialize without requesting UI permissions from background
  await NotificationService.instance.initialize(requestPermission: false);

  AudioPlayer? alarmPlayer;
  bool isAudioPlaying = false;
  Timer? tickerTimer;

  // Tracking triggered state
  String? lastTriggeredScheduleKey;

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
        debugPrint('[BackgroundService Isolate] Alarm audio stopped by user.');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_alarm_triggered', false);

        service.invoke('status', {
          'is_audio_playing': false,
          'is_triggered': false,
        });
      }
    } catch (e) {
      debugPrint('[BackgroundService Isolate] Error stopping alarm: $e');
    }
  }

  // Handle commands from main isolate
  service.on('start_alarm_audio').listen((event) async {
    await playLoopingAlarm();
  });

  service.on('stop_alarm_audio').listen((event) async {
    await stopLoopingAlarm();
  });

  service.on('stopService').listen((event) async {
    await stopLoopingAlarm();
    tickerTimer?.cancel();
    service.stopSelf();
  });

  // Periodic ticker check (every second)
  tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final isAlarmActive = prefs.getBool('is_alarm_triggered') ?? false;

    // Load schedules from SharedPreferences
    final rawList = prefs.getStringList(AppBackgroundService._schedulesKey) ?? [];
    final List<StandingSchedule> schedules = rawList
        .map((e) => StandingSchedule.fromJson(e))
        .where((s) => s.isEnabled)
        .toList();

    final now = DateTime.now();

    // If alarm is already triggered & sounding, maintain status until user dismisses
    if (isAlarmActive || isAudioPlaying) {
      if (!isAudioPlaying) {
        await playLoopingAlarm();
      }
      service.invoke('status', {
        'is_triggered': true,
        'is_audio_playing': true,
        'next_time_str': null,
        'remaining_seconds': 0,
      });
      return;
    }

    if (schedules.isEmpty) {
      service.invoke('status', {
        'is_triggered': false,
        'is_audio_playing': false,
        'next_time_str': null,
        'remaining_seconds': 0,
      });
      return;
    }

    // Find next upcoming schedule & check if current time triggers
    DateTime? nextScheduledDateTime;
    StandingSchedule? nextSchedule;

    for (final schedule in schedules) {
      var candidate = DateTime(
        now.year,
        now.month,
        now.day,
        schedule.hour,
        schedule.minute,
      );

      // Unique trigger key for this specific occurrence
      final occurrenceKey = '${schedule.id}_${now.year}_${now.month}_${now.day}_${schedule.hour}_${schedule.minute}';

      // Check if current time matches schedule (within same minute)
      final diffSeconds = candidate.difference(now).inSeconds;
      if (diffSeconds <= 0 && diffSeconds >= -59) {
        if (lastTriggeredScheduleKey != occurrenceKey) {
          lastTriggeredScheduleKey = occurrenceKey;
          debugPrint('[BackgroundService Isolate] SCHEDULE TIME REACHED: ${schedule.formattedTime}!');
          await prefs.setBool('is_alarm_triggered', true);

          // 1. Show high-priority notification with fullscreen intent
          await NotificationService.instance.showStandingAlertNotification(
            title: '⏰ Standing Time: ${schedule.formattedTime}',
            body: 'Your scheduled standing time has arrived! Tap to open.',
          );

          // 2. Play continuous looping alarm sound
          await playLoopingAlarm();
          return;
        }
      }

      // If scheduled time has already passed today, candidate is for tomorrow
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }

      if (nextScheduledDateTime == null || candidate.isBefore(nextScheduledDateTime)) {
        nextScheduledDateTime = candidate;
        nextSchedule = schedule;
      }
    }

    final remainingSecs = nextScheduledDateTime != null
        ? nextScheduledDateTime.difference(now).inSeconds
        : 0;

    service.invoke('status', {
      'is_triggered': false,
      'is_audio_playing': false,
      'next_time_str': nextSchedule?.formattedTime,
      'remaining_seconds': remainingSecs > 0 ? remainingSecs : 0,
    });
  });
}
