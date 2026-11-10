import 'package:cloud_firestore/cloud_firestore.dart';

class Screening {
  final String id;
  final String userId;
  final double angle;
  final bool hasScoliosis;
  final bool hasPhoto;
  final DateTime createdAt;
  final Map<String, dynamic>? details; // levels of the screening

  /// true = the account holder; false = someone else (see [subject]).
  final bool forSelf;
  final Map<String, dynamic>? subject;

  const Screening({
    required this.id,
    required this.userId,
    required this.angle,
    required this.hasScoliosis,
    required this.hasPhoto,
    required this.createdAt,
    this.details,
    this.forSelf = true,
    this.subject,
  });

  /// The screened person's name when it was for someone else.
  String? get subjectName {
    final s = subject;
    if (s == null) return null;
    return [
      s['firstName'],
      s['middleName'],
      s['lastName'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
  }

  factory Screening.fromMap(String id, Map<String, dynamic> m) => Screening(
    id: id,
    userId: m['userId'] as String,
    angle: (m['angle'] as num).toDouble(),
    hasScoliosis: m['hasScoliosis'] == true,
    hasPhoto: m['hasPhoto'] == true,
    createdAt: m['createdAt'] is Timestamp
        ? (m['createdAt'] as Timestamp).toDate()
        : DateTime.now(),
    details: m['details'] is Map
        ? Map<String, dynamic>.from(m['details'] as Map)
        : null,
    forSelf: m['forSelf'] != false, // older screenings were all for the owner
    subject: m['subject'] is Map
        ? Map<String, dynamic>.from(m['subject'] as Map)
        : null,
  );
}
