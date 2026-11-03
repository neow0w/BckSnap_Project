import 'package:cloud_firestore/cloud_firestore.dart';

class ConsultationMessage {
    final String id;
    final String senderId;
    final String senderRole;
    final String text;
    final DateTime createdAt;

    const ConsultationMessage({
        required this.id,
        required this.senderId,
        required this.senderRole,
        required this.text,
        required this.createdAt,
    });

    factory ConsultationMessage.fromFirestore(
        DocumentSnapshot<Map<String, dynamic>> snapshot,
    ) {
        final data = snapshot.data()!;

        return ConsultationMessage(
            id: snapshot.id,
            senderId: data['senderId'] as String,
            senderRole: data['senderRole'] as String,
            text: data['text'] as String,
            createdAt: data['createdAt'] is Timestamp
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
        );
    }
}