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
