import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';

/// Writes audit log entries: who did what, and when.
/// Where possible an entry is saved in the same batch as the action itself.
class AuditLog {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Map<String, dynamic> _data({
    required String action,
    String? clinicId,
    String? targetType,
    String? targetId,
    String? targetName,
    String? details,
  }) {
    final me = AuthService().currentUser;
    return {
      'clinicId': clinicId ?? me?.clinicId,
      'actorId': me?.id,
      'actorName': me?.displayName ?? '',
      'actorRole': me?.role ?? '',
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'targetName': targetName,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Adds an entry to a batch, so it is saved together with the action.
  static void addTo(
    WriteBatch batch, {
    required String action,
    String? clinicId,
    String? targetType,
    String? targetId,
    String? targetName,
    String? details,
  }) {
    batch.set(
      _db.collection('auditLogs').doc(),
      _data(
        action: action,
        clinicId: clinicId,
        targetType: targetType,
        targetId: targetId,
        targetName: targetName,
        details: details,
      ),
    );
  }

  /// Saves one entry on its own. Never throws: a logging problem must not
  /// stop the person from using the app.
  static Future<void> record({
    required String action,
    String? clinicId,
    String? targetType,
    String? targetId,
    String? targetName,
    String? details,
  }) async {
    try {
      await _db
          .collection('auditLogs')
          .add(
            _data(
              action: action,
              clinicId: clinicId,
              targetType: targetType,
              targetId: targetId,
              targetName: targetName,
              details: details,
            ),
          );
    } catch (_) {}
  }
}
