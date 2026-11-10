import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

import '../../models/doctor_schedule.dart';
import '../../services/doctor_schedule_service.dart';
import 'staff_web_shell.dart';

class WebDoctorSchedulePage extends StatefulWidget {
  const WebDoctorSchedulePage({super.key});

  @override
  State<WebDoctorSchedulePage> createState() => _WebDoctorSchedulePageState();
}

class _WebDoctorSchedulePageState extends State<WebDoctorSchedulePage> {
  final DoctorScheduleService _service = DoctorScheduleService();

  static const List<String> _days = DoctorSchedule.weekdays;

  final Map<String, DoctorDaySchedule> _schedule = {
    for (final day in _days) day: const DoctorDaySchedule(),
  };

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  String _dayName(String day) {
    return '${day[0].toUpperCase()}${day.substring(1)}';
  }

  Future<void> _loadSchedule() async {
    try {
      final saved = await _service.getMySchedule();

      if (saved != null) {
        for (final day in _days) {
          _schedule[day] =
              saved.weeklySchedule[day] ?? const DoctorDaySchedule();
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int _minutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _formatTime(String value) {
    final parts = value.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  void _updateDay(String day, DoctorDaySchedule updated) {
    setState(() {
      _schedule[day] = updated;
    });
  }

  Future<void> _selectTime(
    String day,
    String field,
    String currentValue,
  ) async {
    final parts = currentValue.split(':');

    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );

    if (selected == null || !mounted) return;

    final value =
        '${selected.hour.toString().padLeft(2, '0')}:'
        '${selected.minute.toString().padLeft(2, '0')}';

    final current = _schedule[day]!;

    switch (field) {
      case 'timeIn':
        _updateDay(
          day,
          DoctorDaySchedule(
            enabled: current.enabled,
            timeIn: value,
            timeOut: current.timeOut,
            lunchBreakEnabled: current.lunchBreakEnabled,
            lunchStart: current.lunchStart,
            lunchEnd: current.lunchEnd,
          ),
        );
        break;

      case 'timeOut':
        _updateDay(
          day,
          DoctorDaySchedule(
            enabled: current.enabled,
            timeIn: current.timeIn,
            timeOut: value,
            lunchBreakEnabled: current.lunchBreakEnabled,
            lunchStart: current.lunchStart,
            lunchEnd: current.lunchEnd,
          ),
        );
        break;

      case 'lunchStart':
        _updateDay(
          day,
          DoctorDaySchedule(
            enabled: current.enabled,
            timeIn: current.timeIn,
            timeOut: current.timeOut,
            lunchBreakEnabled: current.lunchBreakEnabled,
            lunchStart: value,
            lunchEnd: current.lunchEnd,
          ),
        );
        break;

      case 'lunchEnd':
        _updateDay(
          day,
          DoctorDaySchedule(
            enabled: current.enabled,
            timeIn: current.timeIn,
            timeOut: current.timeOut,
            lunchBreakEnabled: current.lunchBreakEnabled,
            lunchStart: current.lunchStart,
            lunchEnd: value,
          ),
        );
        break;
    }
  }

  String? _validateSchedule() {
    for (final day in _days) {
      final data = _schedule[day]!;

      if (!data.enabled) continue;

      final start = _minutes(data.timeIn);
      final end = _minutes(data.timeOut);

      if (start >= end) {
        return '${_dayName(day)}: Time Out must be after Time In.';
      }

      if (end - start < 60) {
        return '${_dayName(day)}: Working hours must be at least 60 minutes.';
      }
    }

    if (!_schedule.values.any((day) => day.enabled)) {
      return 'Please enable at least one working day.';
    }

    return null;
  }

  
Future<void> _saveSchedule() async {
  final validationError = _validateSchedule();

  if (validationError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(validationError)),
    );
    return;
  }

  setState(() {
    _saving = true;
    _error = null;
  });

  try {
    final authService = AuthService();
    final account = authService.currentUser;
    final profile = authService.activeProfile;

    if (account == null || profile == null) {
      throw Exception('Please select a staff profile first.');
    }

    if (!['doctor', 'pt'].contains(account.role) ||
        profile.role != account.role) {
      throw Exception(
        'Only the selected Doctor or Physical Therapist profile can manage schedules.',
      );
    }

    if (!profile.isActive) {
      throw Exception('Your staff profile is not active.');
    }

    if (profile.clinicId != account.clinicId) {
      throw Exception('Staff profile does not belong to this clinic.');
    }

    final schedule = DoctorSchedule(
      doctorId: profile.id,
      clinicId: profile.clinicId,
      timezone: 'Asia/Manila',
      appointmentDuration: 60,
      breakDuration: 10,
      weeklySchedule: Map<String, DoctorDaySchedule>.from(
        _schedule,
      ),
    );

    await _service.saveMySchedule(schedule);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your schedule has been saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    if (mounted) {
      setState(() => _error = e.toString());
    }
  } finally {
    if (mounted) {
      setState(() => _saving = false);
    }
  }
}


  Widget _timeField(
    String day,
    String label,
    String field,
    String value,
    IconData icon,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _selectTime(day, field, value),
              icon: Icon(icon, size: 18),
              label: Text(
                _formatTime(value),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(String day) {
    final data = _schedule[day]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dayName(day),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  data.enabled ? 'Available' : 'Unavailable',
                  style: TextStyle(
                    color: data.enabled ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  value: data.enabled,
                  onChanged: (value) {
                    _updateDay(
                      day,
                      DoctorDaySchedule(
                        enabled: value,
                        timeIn: data.timeIn,
                        timeOut: data.timeOut,
                        lunchBreakEnabled: data.lunchBreakEnabled,
                        lunchStart: data.lunchStart,
                        lunchEnd: data.lunchEnd,
                      ),
                    );
                  },
                ),
              ],
            ),

            if (data.enabled) ...[
              const SizedBox(height: 12),

              Row(
                children: [
                  _timeField(
                    day,
                    'TIME IN',
                    'timeIn',
                    data.timeIn,
                    Icons.login,
                  ),
                  const SizedBox(width: 12),
                  _timeField(
                    day,
                    'TIME OUT',
                    'timeOut',
                    data.timeOut,
                    Icons.logout,
                  ),
                ],
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No consultations scheduled for this day.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WebPageHeader(
                title: 'My Schedule',
                subtitle: 'Manage your weekly consultation availability.',
              ),

              const SizedBox(height: 24),

              Card(
                elevation: 0,
                color: Colors.blue.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consultation Settings',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, color: Colors.blue),
                          SizedBox(width: 10),
                          Text('Consultation duration: 60 minutes'),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.coffee_outlined, color: Colors.blue),
                          SizedBox(width: 10),
                          Text('Break between patients: 10 minutes'),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.public, color: Colors.blue),
                          SizedBox(width: 10),
                          Text('Timezone: Asia/Manila'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Weekly Availability',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              Text(
                'Enable the days you accept consultations and set your working hours.',
                style: TextStyle(color: Colors.grey.shade600),
              ),

              const SizedBox(height: 16),

              for (final day in _days) _dayCard(day),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveSchedule,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Schedule'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
