import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/message.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Patient <-> clinic messaging, scoped to a specific clinic.
/// messages/{id}: one message. threads/{clinicId}_{patientId}: inbox row.
class MessageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  dynamic get _me {
    final u = _auth.currentUser;
    if (u == null) throw ApiException(401, 'Please log in again.');
    return u;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  Future<List<ChatMessage>> _thread(String patientId, String clinicId) async {
    final snap = await _db
        .collection('messages')
        .where('patientId', isEqualTo: patientId)
        .where('clinicId', isEqualTo: clinicId)
        .get();
    final list = [
      for (final d in snap.docs) ChatMessage.fromMap(d.id, d.data()),
    ];
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Patient -> clinic.
  Future<void> sendMessage(String clinicId, String body) => _guard(() async {
    final me = _me;
    final name = me.displayName ?? 'Patient';
    final batch = _db.batch();
    batch.set(_db.collection('messages').doc(), {
      'patientId': me.id,
      'patientName': name,
      'clinicId': clinicId,
      'fromPatient': true,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('threads').doc('${clinicId}_${me.id}'), {
      'patientId': me.id,
      'patientName': name,
      'clinicId': clinicId,
      'lastMessage': body,
      'lastFromPatient': true,
      'lastAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  });

  Future<List<ChatMessage>> getMyMessages(String clinicId) =>
      _guard(() => _thread(_me.id, clinicId));

  /// Receptionist: one row per patient conversation of their clinic.
  Future<List<InboxItem>> inbox() => _guard(() async {
    final snap = await _db
        .collection('threads')
        .where('clinicId', isEqualTo: _me.clinicId)
        .get();
    final list = [for (final d in snap.docs) InboxItem.fromMap(d.data())];
    list.sort(
      (a, b) =>
          (b.lastAt ?? DateTime(2000)).compareTo(a.lastAt ?? DateTime(2000)),
    );
    return list;
  });

  Future<List<ChatMessage>> thread(String patientId, String clinicId) =>
      _guard(() => _thread(patientId, clinicId));

  /// Receptionist -> patient.
  Future<void> reply(String patientId, String clinicId, String body) =>
      _guard(() async {
        final batch = _db.batch();
        batch.set(_db.collection('messages').doc(), {
          'patientId': patientId,
          'clinicId': clinicId,
          'fromPatient': false,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.update(_db.collection('threads').doc('${clinicId}_$patientId'), {
          'lastMessage': body,
          'lastFromPatient': false,
          'unreadForPatient': FieldValue.increment(1),
          'lastAt': FieldValue.serverTimestamp(),
        });
        await batch.commit();
      });

  /// Live inbox for the website.
  Stream<List<InboxItem>> inboxStream() {
    return _db
        .collection('threads')
        .where('clinicId', isEqualTo: _me.clinicId)
        .snapshots()
        .map((snap) {
          final list = [for (final d in snap.docs) InboxItem.fromMap(d.data())];
          list.sort(
            (a, b) => (b.lastAt ?? DateTime(2000)).compareTo(
              a.lastAt ?? DateTime(2000),
            ),
          );
          return list;
        });
  }

  /// Live conversation with one patient for the website.
  Stream<List<ChatMessage>> threadStream(String patientId, String clinicId) {
    return _db
        .collection('messages')
        .where('patientId', isEqualTo: patientId)
        .where('clinicId', isEqualTo: clinicId)
        .snapshots()
        .map((snap) {
          final list = [
            for (final d in snap.docs) ChatMessage.fromMap(d.id, d.data()),
          ];
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        });
  }

  /// Live list of this patient's conversations, newest first.
  Stream<List<PatientThread>> myThreadsStream() {
    return _db
        .collection('threads')
        .where('patientId', isEqualTo: _me.id)
        .snapshots()
        .map((snap) {
          final list = [
            for (final d in snap.docs) PatientThread.fromMap(d.data()),
          ];
          list.sort(
            (a, b) => (b.lastAt ?? DateTime(2000)).compareTo(
              a.lastAt ?? DateTime(2000),
            ),
          );
          return list;
        });
  }

  /// Total unread messages, for the small badges.
  Stream<int> unreadCountStream() => myThreadsStream().map(
    (list) => list.fold<int>(0, (total, t) => total + t.unread),
  );

  /// The patient opened the conversation with this clinic.
  Future<void> markThreadRead(String clinicId) async {
    try {
      await _db.collection('threads').doc('${clinicId}_${_me.id}').update({
        'unreadForPatient': 0,
      });
    } catch (_) {} // no thread yet, or offline: nothing to do
  }
}
