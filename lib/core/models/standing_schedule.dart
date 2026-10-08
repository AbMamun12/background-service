import 'dart:convert';

class StandingSchedule {
  final String id;
  final int hour;
  final int minute;
  final bool isEnabled;

  const StandingSchedule({
    required this.id,
    required this.hour,
    required this.minute,
    this.isEnabled = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'isEnabled': isEnabled,
    };
  }

  factory StandingSchedule.fromMap(Map<String, dynamic> map) {
    return StandingSchedule(
      id: map['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      hour: (map['hour'] as num?)?.toInt() ?? 0,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
      isEnabled: map['isEnabled'] as bool? ?? true,
    );
  }

  String toJson() => json.encode(toMap());

  factory StandingSchedule.fromJson(String source) =>
      StandingSchedule.fromMap(json.decode(source) as Map<String, dynamic>);

  StandingSchedule copyWith({
    String? id,
    int? hour,
    int? minute,
    bool? isEnabled,
  }) {
    return StandingSchedule(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  String get formattedTime {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}
