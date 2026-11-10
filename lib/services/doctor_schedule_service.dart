
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/doctor_schedule.dart';
import 'auth_service.dart';

class DoctorScheduleService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthService _authService;

  DoctorScheduleService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuthService? authService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _authService = authService ?? AuthService();

  /// Returns the selected Doctor or Physical Therapist profile ID.
  String get _staffProfileId {
    if (_auth.currentUser == null) {
      throw Exception('You must be logged in to manage schedules.');
    }

    final account = _authService.currentUser;
    final profile = _authService.activeProfile;

    if (account == null || profile == null) {
      throw Exception('Please select a staff profile first.');
    }

    if (!['doctor', 'pt'].contains(account.role) ||
        profile.role != account.role) {
      throw Exception(
        'Only Doctor and Physical Therapist profiles can manage schedules.',
      );
    }

    if (!profile.isActive) {
      throw Exception('Your staff profile is not active.');
    }

    if (profile.clinicId != account.clinicId) {
      throw Exception('Staff profile does not belong to this clinic.');
    }

    return profile.id;
  }

  /// Loads and verifies the currently selected staff profile.
  Future<DocumentSnapshot<Map<String, dynamic>>> _getStaffProfile() async {
    final profileId = _staffProfileId;

    final snapshot = await _firestore
        .collection('staffProfiles')
        .doc(profileId)
        .get();

    if (!snapshot.exists) {
      throw Exception('Staff profile was not found.');
    }

    final data = snapshot.data()!;
    final account = _authService.currentUser!;

    if (!['doctor', 'pt'].contains(account.role) ||
        data['role'] != account.role) {
      throw Exception(
        'Only the selected Doctor or Physical Therapist can manage this schedule.',
      );
    }

    if (data['status'] != 'active') {
      throw Exception('Your staff profile is not active.');
    }

    if (data['clinicId'] != account.clinicId) {
      throw Exception('Staff profile does not belong to this clinic.');
    }

    return snapshot;
  }

  /// Loads the selected staff member's saved weekly schedule.
  Future<DoctorSchedule?> getMySchedule() async {
    final profile = await _getStaffProfile();

    final snapshot = await _firestore
        .collection('doctorSchedules')
        .doc(profile.id)
        .get();

    if (!snapshot.exists) return null;

    return DoctorSchedule.fromMap(snapshot.data()!);
  }

  /// Saves or updates only the selected staff member's weekly schedule.
  Future<void> saveMySchedule(DoctorSchedule schedule) async {
    final profile = await _getStaffProfile();

    final profileId = profile.id;
    final clinicId = profile.data()!['clinicId'] as String?;

    if (clinicId == null || clinicId.isEmpty) {
      throw Exception('Staff profile is not assigned to a clinic.');
    }

    // doctorId is retained in the existing model for backward compatibility.
    // For PT schedules, it stores the PT's own staff profile ID.
    if (schedule.doctorId != profileId) {
      throw Exception(
        'You cannot save another staff member\'s schedule.',
      );
    }

    if (schedule.clinicId != clinicId) {
      throw Exception(
        'The schedule clinic does not match the staff profile.',
      );
    }

    await _firestore
        .collection('doctorSchedules')
        .doc(profileId)
        .set({
          ...schedule.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Checks whether the selected staff member has configured a schedule.
  Future<bool> hasSchedule() async {
    final schedule = await getMySchedule();
    return schedule != null;
  }
}
