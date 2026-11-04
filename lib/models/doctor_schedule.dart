
class DoctorDaySchedule {
  final bool enabled;
  final String timeIn;
  final String timeOut;
  final bool lunchBreakEnabled;
  final String lunchStart;
  final String lunchEnd;

  const DoctorDaySchedule({
    this.enabled = false,
    this.timeIn = '08:00',
    this.timeOut = '17:00',
    this.lunchBreakEnabled = false,
    this.lunchStart = '12:00',
    this.lunchEnd = '13:00',
  });

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'timeIn': timeIn,
      'timeOut': timeOut,
      'lunchBreakEnabled': lunchBreakEnabled,
      'lunchStart': lunchStart,
      'lunchEnd': lunchEnd,
    };
  }

  factory DoctorDaySchedule.fromMap(Map<String, dynamic> map) {
    // Supports older schedules that used working periods.
    final legacyPeriods = map['periods'] as List<dynamic>? ?? [];
    final legacyPeriod = legacyPeriods.isNotEmpty &&
            legacyPeriods.first is Map
        ? Map<String, dynamic>.from(legacyPeriods.first as Map)
        : <String, dynamic>{};

    return DoctorDaySchedule(
      enabled: map['enabled'] as bool? ?? false,
      timeIn: map['timeIn'] as String? ??
          legacyPeriod['start'] as String? ??
          '08:00',
      timeOut: map['timeOut'] as String? ??
          legacyPeriod['end'] as String? ??
          '17:00',
      lunchBreakEnabled:
          map['lunchBreakEnabled'] as bool? ?? false,
      lunchStart: map['lunchStart'] as String? ?? '12:00',
      lunchEnd: map['lunchEnd'] as String? ?? '13:00',
    );
  }
}

class DoctorSchedule {
  final String doctorId;
  final String clinicId;
  final String timezone;
  final int appointmentDuration;
  final int breakDuration;
  final Map<String, DoctorDaySchedule> weeklySchedule;

  const DoctorSchedule({
    required this.doctorId,
    required this.clinicId,
    this.timezone = 'Asia/Manila',
    this.appointmentDuration = 60,
    this.breakDuration = 10,
    required this.weeklySchedule,
  });

  static const weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  Map<String, dynamic> toMap() {
    return {
      'doctorId': doctorId,
      'clinicId': clinicId,
      'timezone': timezone,
      'appointmentDuration': appointmentDuration,
      'breakDuration': breakDuration,
      'weeklySchedule': {
        for (final day in weekdays)
          day: (weeklySchedule[day] ?? const DoctorDaySchedule()).toMap(),
      },
    };
  }

  factory DoctorSchedule.fromMap(Map<String, dynamic> map) {
    final rawSchedule =
        Map<String, dynamic>.from(map['weeklySchedule'] as Map? ?? {});

    return DoctorSchedule(
      doctorId: map['doctorId'] as String? ?? '',
      clinicId: map['clinicId'] as String? ?? '',
      timezone: map['timezone'] as String? ?? 'Asia/Manila',
      appointmentDuration: map['appointmentDuration'] as int? ?? 60,
      breakDuration: map['breakDuration'] as int? ?? 10,
      weeklySchedule: {
        for (final day in weekdays)
          day: DoctorDaySchedule.fromMap(
            Map<String, dynamic>.from(rawSchedule[day] as Map? ?? {}),
          ),
      },
    );
  }
}
