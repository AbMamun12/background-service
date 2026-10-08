import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/standing_schedule.dart';
import '../../../core/services/background_service.dart';
import '../../standing/views/standing_overlay_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<StandingSchedule> _schedules = [];
  int _remainingSeconds = 0;
  String? _nextTimeStr;
  bool _isAlarmTriggered = false;
  bool _isAudioPlaying = false;

  String _selectedSound = 'audio/audio_1.wav';
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewPlaying = false;

  StreamSubscription? _statusSubscription;

  final List<Map<String, String>> _availableSounds = [
    {'name': 'Chime Alarm 1', 'path': 'audio/audio_1.wav'},
    {'name': 'Soft Melody 2', 'path': 'audio/audio_2.wav'},
    {'name': 'Alert Bell 3', 'path': 'audio/audio_3.wav'},
    {'name': 'Gentle Tone 4', 'path': 'audio/audio_4.wav'},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();

    // Listen to background service status stream
    _statusSubscription = AppBackgroundService.onStatusChange.listen((status) {
      if (status != null && mounted) {
        final isTriggered = status['is_triggered'] ?? false;
        final isAudioPlaying = status['is_audio_playing'] ?? false;
        setState(() {
          _remainingSeconds = status['remaining_seconds'] ?? 0;
          _nextTimeStr = status['next_time_str'];
          _isAlarmTriggered = isTriggered;
          _isAudioPlaying = isAudioPlaying;
        });

        if ((isTriggered || isAudioPlaying) && !StandingOverlayView.isStandingOverlayActive) {
          _openStandingOverlay();
        }
      }
    });
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSchedules = await AppBackgroundService.getSchedules();

    // If initial empty state, provide default schedules e.g., 10:30 AM & 03:00 PM
    if (savedSchedules.isEmpty) {
      final defaultSchedules = [
        const StandingSchedule(id: '1', hour: 10, minute: 30, isEnabled: true),
        const StandingSchedule(id: '2', hour: 15, minute: 0, isEnabled: true),
      ];
      await AppBackgroundService.saveSchedules(defaultSchedules);
      _schedules = defaultSchedules;
    } else {
      _schedules = savedSchedules;
    }

    final isTriggered = prefs.getBool('is_alarm_triggered') ?? false;

    if (mounted) {
      setState(() {
        _selectedSound = prefs.getString('alarm_sound') ?? 'audio/audio_1.wav';
        _isAlarmTriggered = isTriggered;
      });

      if (isTriggered && !StandingOverlayView.isStandingOverlayActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openStandingOverlay();
        });
      }
    }
  }

  Future<void> _setAlarmSound(String soundPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_sound', soundPath);
    setState(() {
      _selectedSound = soundPath;
    });
  }

  Future<void> _togglePreviewSound(String soundPath) async {
    if (_isPreviewPlaying) {
      await _previewPlayer.stop();
      setState(() {
        _isPreviewPlaying = false;
      });
    } else {
      await _previewPlayer.play(AssetSource(soundPath));
      setState(() {
        _isPreviewPlaying = true;
      });
      _previewPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPreviewPlaying = false;
          });
        }
      });
    }
  }

  Future<void> _pickAndAddNewSchedule() async {
    final now = TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: 'SELECT STANDING TIME',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.card,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      await AppBackgroundService.addSchedule(pickedTime.hour, pickedTime.minute);
      final updated = await AppBackgroundService.getSchedules();
      setState(() {
        _schedules = updated;
      });

      if (mounted) {
        final formatted = pickedTime.format(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scheduled reminder added for $formatted'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleSchedule(String id, bool enabled) async {
    await AppBackgroundService.toggleSchedule(id, enabled);
    final updated = await AppBackgroundService.getSchedules();
    setState(() {
      _schedules = updated;
    });
  }

  Future<void> _deleteSchedule(String id) async {
    await AppBackgroundService.deleteSchedule(id);
    final updated = await AppBackgroundService.getSchedules();
    setState(() {
      _schedules = updated;
    });
  }

  void _openStandingOverlay() {
    if (StandingOverlayView.isStandingOverlayActive) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StandingOverlayView(),
        fullscreenDialog: true,
      ),
    );
  }

  String _formatRemaining(int seconds) {
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${mins.toString().padLeft(2, '0')}m';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.accessibility_new_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'DeskFit Standing Schedule',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. Live Background Status & Next Scheduled Alert Card
          _buildLiveStatusCard(),

          const SizedBox(height: 24),

          // 2. Schedule Times Management Section
          _buildScheduleManagementSection(),

          const SizedBox(height: 24),

          // 3. Sound Selector Section
          _buildSoundSelectorSection(),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard() {
    Color statusColor = AppColors.textMuted;
    String statusTitle = 'NO ACTIVE SCHEDULES';
    String statusSub = 'Add one or more standing times below';

    final hasEnabled = _schedules.any((s) => s.isEnabled);

    if (_isAlarmTriggered || _isAudioPlaying) {
      statusColor = AppColors.danger;
      statusTitle = 'ALARM IS RINGING';
      statusSub = 'Scheduled time reached! Looping until stopped.';
    } else if (hasEnabled && _nextTimeStr != null) {
      statusColor = AppColors.primary;
      statusTitle = 'SCHEDULE ACTIVE';
      statusSub = 'Next standing reminder at $_nextTimeStr';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: statusColor, blurRadius: 8, spreadRadius: 2),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                statusTitle,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_remainingSeconds > 0 && !_isAlarmTriggered) ...[
            Text(
              _formatRemaining(_remainingSeconds),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            statusSub,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          if (_isAlarmTriggered || _isAudioPlaying) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openStandingOverlay,
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('OPEN STANDING OVERLAY / STOP ALARM'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildScheduleManagementSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Standing Times',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _pickAndAddNewSchedule,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Time'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select the times of day you want standing posture reminders:',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (_schedules.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Icon(Icons.schedule, color: AppColors.textMuted, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'No scheduled times added yet.',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _schedules.map((schedule) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: schedule.isEnabled ? AppColors.primary.withValues(alpha: 0.3) : AppColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: schedule.isEnabled
                              ? AppColors.primary.withValues(alpha: 0.15)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.access_time_filled_rounded,
                          color: schedule.isEnabled ? AppColors.primary : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          schedule.formattedTime,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: schedule.isEnabled ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                        ),
                      ),
                      Switch(
                        value: schedule.isEnabled,
                        activeTrackColor: AppColors.primary,
                        activeThumbColor: Colors.white,
                        onChanged: (val) => _toggleSchedule(schedule.id, val),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                        onPressed: () => _deleteSchedule(schedule.id),
                        tooltip: 'Delete schedule',
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSoundSelectorSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Alarm Sound',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: Icon(
                  _isPreviewPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  color: _isPreviewPlaying ? AppColors.danger : AppColors.primary,
                ),
                onPressed: () => _togglePreviewSound(_selectedSound),
                tooltip: _isPreviewPlaying ? 'Stop preview' : 'Play preview',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: _availableSounds.map((sound) {
              final isSelected = _selectedSound == sound['path'];
              return InkWell(
                onTap: () => _setAlarmSound(sound['path']!),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.cardBorder,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: isSelected ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          sound['name']!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
