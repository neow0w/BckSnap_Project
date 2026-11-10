import 'package:cloud_firestore/cloud_firestore.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// A clinic's request to join BckSnap.
class ClinicRegistration {
  final String id; // same as the applicant's user id
  final String applicantId;
  final String applicantName;
  final String applicantEmail;
  final String clinicName;
  final String address;
  final String phone;
  final String clinicEmail;
  final String? description;
  final String? licenseNumber;
  final List<String> services;
  final bool supportsPhysical;
  final bool supportsOnline;
  final String status; // pending / approved / rejected
  final String? rejectionReason;
  final DateTime? createdAt;

  const ClinicRegistration({
    required this.id,
    required this.applicantId,
    required this.applicantName,
    required this.applicantEmail,
    required this.clinicName,
    required this.address,
    required this.phone,
    required this.clinicEmail,
    required this.services,
    required this.supportsPhysical,
    required this.supportsOnline,
    required this.status,
    this.description,
    this.licenseNumber,
    this.rejectionReason,
    this.createdAt,
  });

  factory ClinicRegistration.fromMap(String id, Map<String, dynamic> m) =>
      ClinicRegistration(
        id: id,
        applicantId: (m['applicantId'] ?? id).toString(),
        applicantName: (m['applicantName'] ?? '').toString(),
        applicantEmail: (m['applicantEmail'] ?? '').toString(),
        clinicName: (m['clinicName'] ?? 'Clinic').toString(),
        address: (m['address'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        clinicEmail: (m['clinicEmail'] ?? '').toString(),
        description: m['description'] as String?,
        licenseNumber: m['licenseNumber'] as String?,
        services: [
          for (final s in (m['services'] as List? ?? const [])) s.toString(),
        ],
        supportsPhysical: m['supportsPhysical'] == true,
        supportsOnline: m['supportsOnline'] == true,
        status: (m['status'] ?? 'pending').toString(),
        rejectionReason: m['rejectionReason'] as String?,
        createdAt: m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate()
            : null,
      );
}

/// The developer reviews clinic registrations.
class ClinicRegistrationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  dynamic get _me {
    final u = AuthService().currentUser;
    if (u == null || u.role != 'developer') {
      throw ApiException(
        403,
        'Only the developer can review clinic registrations.',
      );
    }
    return u;
  }

  /// Live list, newest first.
  Stream<List<ClinicRegistration>> stream() {
    return _db.collection('clinicRegistrations').snapshots().map((snap) {
      final list = [
        for (final d in snap.docs) ClinicRegistration.fromMap(d.id, d.data()),
      ];
      final now = DateTime.now();
      list.sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
      return list;
    });
  }

  /// Creates the clinic and activates the applicant as its administrator.
  Future<void> approve(
    ClinicRegistration r, {
    double? latitude,
    double? longitude,
  }) async {
    final me = _me;
    try {
      final clinicRef = _db.collection('clinics').doc();
      final batch = _db.batch();
      batch.set(clinicRef, {
        'name': r.clinicName,
        'description': r.description,
        'address': r.address,
        'latitude': latitude,
        'longitude': longitude,
        'phone': r.phone,
        'email': r.clinicEmail,
        'timezone': 'Asia/Manila',
        'operatingHours': <String, dynamic>{},
        'supportsOnline': r.supportsOnline,
        'supportsPhysical': r.supportsPhysical,
        'services': r.services,
        'registrationId': r.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(_db.collection('users').doc(r.applicantId), {
        'status': 'active',
        'clinicId': clinicRef.id,
      });
      batch.update(_db.collection('clinicRegistrations').doc(r.id), {
        'status': 'approved',
        'clinicId': clinicRef.id,
        'rejectionReason': null,
        'reviewedBy': me.id,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  Future<void> reject(ClinicRegistration r, String reason) async {
    final me = _me;
    try {
      final batch = _db.batch();
      batch.update(_db.collection('users').doc(r.applicantId), {
        'status': 'rejected',
      });
      batch.update(_db.collection('clinicRegistrations').doc(r.id), {
        'status': 'rejected',
        'rejectionReason': reason.trim().isEmpty ? null : reason.trim(),
        'reviewedBy': me.id,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }
}
