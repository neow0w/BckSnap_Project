const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "12 Oct 2010"
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "2010-10-12" (what the API expects for a date)
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Today's date at the clinic, as "2026-11-05". The clinic works on
/// Philippine time (UTC+8, no daylight saving), whatever the device clock says.
String clinicToday() =>
    isoDate(DateTime.now().toUtc().add(const Duration(hours: 8)));

/// A doctor counts as "in" only when the status was set for today.
/// Yesterday's status expires by itself.
bool isPresentToday(String? presentOn) =>
    presentOn != null && presentOn == clinicToday();

/// "3:05 PM"
String formatTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// "12 Oct 2010, 3:05 PM"
String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatTime(d)}';
