import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/image_compress.dart';
import '../models/screening.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'audit_log.dart';

class ScreeningService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Same limit as ResultRules.referAtr.
  static const double _referAtr = 7.0;

  /// Saves one screening, with the compressed back photo if we have one.
  Future<String?> saveScreening({
    required double angle,
    Uint8List? photoBytes,
    String? photoName,
    Map<String, dynamic>? details,
    bool forSelf = true,
    Map<String, dynamic>? subject,
  }) async {
    final me = AuthService().currentUser;
    if (me == null) throw ApiException(401, 'Please log in again.');
    try {
      final small = photoBytes == null
          ? null
          : await ImageCompressor.shrink(
              photoBytes,
              maxSide: 720,
              quality: 60,
              maxBytes: 120 * 1024,
            );
      final ref = _db.collection('screenings').doc();
      final batch = _db.batch();
      batch.set(ref, {
        'userId': me.id,
        'angle': angle,
        'hasScoliosis': angle >= _referAtr,
        'hasPhoto': small != null,
        'details': details,
        'forSelf': forSelf,
        'subject': subject,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (small != null) {
        batch.set(_db.collection('screeningPhotos').doc(ref.id), {
          'userId': me.id,
          'data': Blob(small),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return ref.id;
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// The logged-in user's screenings, newest first.
  Future<List<Screening>> myScreenings() async {
    final me = AuthService().currentUser;
    if (me == null) return [];
    try {
      final snap = await _db
          .collection('screenings')
          .where('userId', isEqualTo: me.id)
          .get();
      final list = [
        for (final d in snap.docs) Screening.fromMap(d.id, d.data()),
      ].where((s) => s.forSelf).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// Leaves a "monthly check-up" notification for this screening (once).
  Future<void> createDueReminder(Screening latest) async {
    final me = AuthService().currentUser;
    if (me == null) return;
    try {
      final existing = await _db
          .collection('notifications')
          .where('userId', isEqualTo: me.id)
          .get();
      final already = existing.docs.any(
        (d) => d.data()['screeningId'] == latest.id,
      );
      if (already) return;
      await _db.collection('notifications').doc('due_${latest.id}').set({
        'userId': me.id,
        'screeningId': latest.id,
        'appointmentId': '',
        'eventType': 'screening_due',
        'title': 'Time for your monthly check-up',
        'message':
            'It has been a month since your last screening. Repeat the '
            'screening and scoliometer reading to see how you are doing.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // A reminder is a nice-to-have: never block the home screen on it.
    }
  }

  /// Staff: one patient's screenings, newest first.
  Future<List<Screening>> screeningsOf(String userId) async {
    final viewer = AuthService().currentUser;
    if (viewer != null && viewer.role != 'user' && viewer.id != userId) {
      AuditLog.record(
        action: 'screening.viewed',
        targetType: 'user',
        targetId: userId,
      );
    }
    try {
      final snap = await _db
          .collection('screenings')
          .where('userId', isEqualTo: userId)
          .get();
      final list = [
        for (final d in snap.docs) Screening.fromMap(d.id, d.data()),
      ];
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// Staff: the compressed back photo of one screening (null if none).
  Future<Uint8List?> photoOf(String screeningId) async {
    final viewer = AuthService().currentUser;
    if (viewer != null && viewer.role != 'user') {
      AuditLog.record(
        action: 'screening.photo_viewed',
        targetType: 'screening',
        targetId: screeningId,
      );
    }
    try {
      final snap = await _db
          .collection('screeningPhotos')
          .doc(screeningId)
          .get();
      final data = snap.data()?['data'];
      return data is Blob ? data.bytes : null;
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }
}
