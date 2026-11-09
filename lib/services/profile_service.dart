import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/profile_crypto.dart';
import '../models/staff_profile.dart';
import 'api_client.dart';
import 'audit_log.dart';
import 'auth_service.dart';
import '../core/format.dart';

/// The doctor and receptionist profiles of a clinic.
/// staffProfiles/{id}: one profile.
/// doctors/{id}: the public card patients book (same id), created when a
/// doctor profile becomes active.
class ProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  dynamic get _me {
    final u = _auth.currentUser;
    if (u == null) throw ApiException(401, 'Please log in again.');
    return u;
  }

  String _providerType(StaffProfile p) {
    if (p.role == 'pt') {
      return 'Physical Therapist';
    }

    return p.professionalType;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  void _requireAdmin() {
    if (_me.role != 'admin') {
      throw ApiException(403, 'Only the clinic administrator can do that.');
    }
  }

  static Map<String, dynamic> _doctorCard(
    String id,
    String clinicId,
    String name,
    String professionalType,
    List<String> professions,
  ) {
    final requiresReferral = professionalType == 'Physical Therapist';

    return {
      'userId': id,
      'clinicId': clinicId,
      'name': name,
      'professionalType': professionalType,
      'specializations': professions,
      'requiresReferral': requiresReferral,
      'supportsOnline': true,
      'supportsPhysical': true,
      'active': true,
    };
  }

  /// All profiles of the clinic (or only the active ones).
  Future<List<StaffProfile>> profiles({bool activeOnly = false}) => _guard(
    () async {
      final snap = await _db
          .collection('staffProfiles')
          .where('clinicId', isEqualTo: _me.clinicId)
          .get();
      final list = [
        for (final d in snap.docs) StaffProfile.fromMap(d.id, d.data()),
      ];
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return activeOnly ? list.where((p) => p.isActive).toList() : list;
    },
  );

  /// Live map of doctor id -> the date the doctor was marked "in".
  /// Use [isPresentToday] on the value (an old date means "out").
  Stream<Map<String, String>> doctorPresenceStream() => _db
      .collection('doctors')
      .where('clinicId', isEqualTo: _me.clinicId)
      .snapshots()
      .map(
        (snap) => {
          for (final d in snap.docs)
            if (d.data()['presentOn'] is String)
              d.id: d.data()['presentOn'] as String,
        },
      );

  /// Receptionist: mark a doctor as in the clinic today, or as out.
  /// The status is stored as today's date, so it resets by itself each day.
  Future<void> setDoctorPresent(StaffProfile p, bool present) =>
      _guard(() async {
        if (_me.role != 'receptionist') {
          throw ApiException(
            403,
            "Only the receptionist can change a doctor's status.",
          );
        }
        if (!p.isDoctor || !p.isActive) {
          throw ApiException(400, 'Only active doctors can be marked in.');
        }
        final batch = _db.batch();
        batch.update(_db.collection('doctors').doc(p.id), {
          'presentOn': present ? clinicToday() : FieldValue.delete(),
        });
        AuditLog.addTo(
          batch,
          action: 'doctor.presence_changed',
          targetType: 'profile',
          targetId: p.id,
          targetName: p.name,
          details: present ? 'in' : 'out',
        );
        await batch.commit();
      });

  /// Admin: the clinic's shared staff account, or null if not created yet.
  Future<Map<String, dynamic>?> staffAccount() => _guard(() async {
    final snap = await _db
        .collection('users')
        .where('clinicId', isEqualTo: _me.clinicId)
        .where('role', isEqualTo: 'clinic_staff')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return {
      'id': d.id,
      'email': d.data()['email'],
      'status': d.data()['status'] ?? 'active',
    };
  });

  /// Admin: creates profiles active immediately.
  /// Other staff: creates doctor, PT, or receptionist profiles pending approval.
  Future<void> createProfile({
    required String name,
    required String role,
    required String password,
    String professionalType = 'Doctor',
    List<String> professions = const [],
  }) => _guard(() async {
    final me = _me;
    final isAdmin = me.role == 'admin';

    const allowedCreators = {
      'admin',
      'clinic_staff',
      'receptionist',
      'doctor',
      'pt',
    };

    const allowedProfileRoles = {'doctor', 'pt', 'receptionist'};

    if (!allowedCreators.contains(me.role)) {
      throw ApiException(403, 'Your account cannot create staff profiles.');
    }

    if (!allowedProfileRoles.contains(role)) {
      throw ApiException(
        400,
        'You can only create doctor, physical therapist, or receptionist profiles.',
      );
    }

    final clinicId = me.clinicId as String?;
    if (clinicId == null) {
      throw ApiException(403, 'No clinic is assigned to this account.');
    }

    final cleanName = name.trim();
    final status = isAdmin ? 'active' : 'pending';
    final salt = ProfileCrypto.newSalt();
    final ref = _db.collection('staffProfiles').doc();
    final batch = _db.batch();

    batch.set(ref, {
      'clinicId': clinicId,
      'name': cleanName,
      'role': role,
      'professionalType': role == 'pt'
          ? 'Physical Therapist'
          : professionalType,
      'status': status,
      'professions': (role == 'doctor' || role == 'pt')
          ? professions
          : <String>[],
      'passwordSalt': salt,
      'passwordHash': ProfileCrypto.hash(salt, password),
      'createdByName': me.displayName,
      'createdByRole': me.role,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (status == 'active' && (role == 'doctor' || role == 'pt')) {
      final providerType = role == 'pt'
          ? 'Physical Therapist'
          : professionalType;
      batch.set(
        _db.collection('doctors').doc(ref.id),
        _doctorCard(ref.id, clinicId, cleanName, providerType, professions),
      );
    }

    AuditLog.addTo(
      batch,
      action: 'profile.created',
      targetType: 'profile',
      targetId: ref.id,
      targetName: cleanName,
      details: '$role${status == 'pending' ? ', waiting for approval' : ''}',
    );

    await batch.commit();
  });

  /// Admin: approve or reject a profile that is waiting.
  Future<void> review(StaffProfile p, {required bool approve}) =>
      _guard(() async {
        _requireAdmin();
        final batch = _db.batch();
        batch.update(_db.collection('staffProfiles').doc(p.id), {
          'status': approve ? 'active' : 'rejected',
          'reviewedBy': _me.id,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
        if (approve && (p.role == 'doctor' || p.role == 'pt')) {
          batch.set(
            _db.collection('doctors').doc(p.id),
            _doctorCard(
              p.id,
              p.clinicId,
              p.name,
              _providerType(p),
              p.professions,
            ),
          );
        }
        AuditLog.addTo(
          batch,
          action: approve ? 'profile.approved' : 'profile.rejected',
          targetType: 'profile',
          targetId: p.id,
          targetName: p.name,
          details: p.role,
        );
        await batch.commit();
      });

  /// Admin: activate or deactivate a profile.
  Future<void> setActive(StaffProfile p, bool active) => _guard(() async {
    _requireAdmin();
    final batch = _db.batch();
    batch.update(_db.collection('staffProfiles').doc(p.id), {
      'status': active ? 'active' : 'inactive',
      if (p.role == 'pt') 'professionalType': 'Physical Therapist',
    });
    // A doctor is only bookable by patients while active.
    if (p.role == 'doctor' || p.role == 'pt') {
      batch.set(_db.collection('doctors').doc(p.id), {
        ..._doctorCard(
          p.id,
          p.clinicId,
          p.name,
          _providerType(p),
          p.professions,
        ),
        'active': active,
      }, SetOptions(merge: true));
    }
    if (p.role == 'pt') {
      batch.update(_db.collection('staffProfiles').doc(p.id), {
        'professionalType': 'Physical Therapist',
      });
    }
    AuditLog.addTo(
      batch,
      action: active ? 'profile.activated' : 'profile.deactivated',
      targetType: 'profile',
      targetId: p.id,
      targetName: p.name,
      details: p.role,
    );
    await batch.commit();
  });

  /// Admin: set a new password for a profile.
  Future<void> resetPassword(StaffProfile p, String newPassword) =>
      _guard(() async {
        _requireAdmin();
        final salt = ProfileCrypto.newSalt();
        final batch = _db.batch();
        batch.update(_db.collection('staffProfiles').doc(p.id), {
          'passwordSalt': salt,
          'passwordHash': ProfileCrypto.hash(salt, newPassword),
        });
        AuditLog.addTo(
          batch,
          action: 'profile.password_reset',
          targetType: 'profile',
          targetId: p.id,
          targetName: p.name,
          details: p.role,
        );
        await batch.commit();
      });
}
