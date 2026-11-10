import 'package:cloud_firestore/cloud_firestore.dart';

/// One message in a patient <-> clinic thread.
class ChatMessage {
  final String id;
  final String body;
  final bool fromPatient;
  final DateTime createdAt; // local time

  const ChatMessage({
    required this.id,
    required this.body,
    required this.fromPatient,
    required this.createdAt,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> m) => ChatMessage(
    id: id,
    body: (m['body'] ?? '') as String,
    fromPatient: m['fromPatient'] == true,
    createdAt: m['createdAt'] is Timestamp
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
  );
}

/// One row of the receptionist's inbox (one patient conversation).
class InboxItem {
  final String patientId;
  final String patientName;
  final String lastMessage;
  final DateTime? lastAt;

  const InboxItem({
    required this.patientId,
    required this.patientName,
    required this.lastMessage,
    this.lastAt,
  });

  factory InboxItem.fromMap(Map<String, dynamic> m) => InboxItem(
    patientId: m['patientId'] as String,
    patientName: (m['patientName'] ?? 'Patient').toString(),
    lastMessage: (m['lastMessage'] ?? '').toString(),
    lastAt: m['lastAt'] is Timestamp
        ? (m['lastAt'] as Timestamp).toDate()
        : null,
  );
}

String timeLabel(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day}/${d.month} $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// One conversation row on the patient's Messages tab.
class PatientThread {
  final String clinicId;
  final String lastMessage;
  final DateTime? lastAt;
  final bool? lastFromPatient; // null on older threads
  final int unread;

  const PatientThread({
    required this.clinicId,
    required this.lastMessage,
    this.lastAt,
    this.lastFromPatient,
    this.unread = 0,
  });

  factory PatientThread.fromMap(Map<String, dynamic> m) => PatientThread(
    clinicId: (m['clinicId'] ?? '').toString(),
    lastMessage: (m['lastMessage'] ?? '').toString(),
    lastAt: m['lastAt'] is Timestamp
        ? (m['lastAt'] as Timestamp).toDate()
        : null,
    lastFromPatient: m['lastFromPatient'] as bool?,
    unread: (m['unreadForPatient'] as num?)?.toInt() ?? 0,
  );
}

/// "3:05 PM" today, "Yesterday", otherwise "12/10".
String shortTimeLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
  if (diff == 1) return 'Yesterday';
  return '${d.day}/${d.month}';
}
