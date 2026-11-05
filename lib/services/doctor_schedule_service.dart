import 'package:cloud_firestore/cloud_firestore.dart';

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
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _authService = authService ?? AuthService();

  /// The selected staff profile ID, NOT the clinic Firebase Auth UID.
  String get _doctorId {
    if (_auth.currentUser == null) {
      throw Exception('You must be logged in to manage schedules.');
    }

    final account = _authService.currentUser;
    final profile = _authService.activeProfile;

    if (account == null || profile == null) {
      throw Exception('Please select a doctor profile first.');
    }

    if (account.role != 'doctor' || !profile.isDoctor) {
      throw Exception('Only doctor profiles can manage schedules.');
    }

    if (!profile.isActive) {
      throw Exception('Your doctor profile is not active.');
    }

    if (profile.clinicId != account.clinicId) {
      throw Exception('Doctor profile does not belong to this clinic.');
    }

    return profile.id;
  }

  /// Loads and verifies the selected doctor profile.
  Future<DocumentSnapshot<Map<String, dynamic>>>
      _getDoctorAccount() async {
    final doctorId = _doctorId;

    final snapshot = await _firestore
        .collection('staffProfiles')
        .doc(doctorId)
        .get();

    if (!snapshot.exists) {
      throw Exception('Doctor profile was not found.');
    }

    final data = snapshot.data()!;

    if (data['role'] != 'doctor') {
      throw Exception('Only doctor profiles can manage schedules.');
    }
    return u.profileId ?? u.id;
  }

    if (data['status'] != 'active') {
      throw Exception('Your doctor profile is not active.');
    }

    final account = _authService.currentUser!;

    if (data['clinicId'] != account.clinicId) {
      throw Exception('Doctor profile does not belong to this clinic.');
    }
    return id;
  }

  /// Loads the selected doctor's saved schedule.
  Future<DoctorSchedule?> getMySchedule() async {
    final snapshot = await _firestore
        .collection('doctorSchedules')
        .doc(doctorId)
        .get();
    if (!snapshot.exists) return null;
    return DoctorSchedule.fromMap(snapshot.data()!);
  }

  /// Saves or updates the selected doctor's weekly schedule.
  Future<void> saveMySchedule(DoctorSchedule schedule) async {
    final account = await _getDoctorAccount();
    final accountData = account.data()!;
    final clinicId = accountData['clinicId'] as String?;
    final doctorId = _doctorId;

    if (clinicId == null || clinicId.isEmpty) {
      throw Exception('Doctor profile is not assigned to a clinic.');
    }

    if (schedule.doctorId != doctorId) {
      throw Exception('You cannot save another doctor\'s schedule.');
    }

    if (schedule.clinicId != clinicId) {
      throw Exception('The schedule clinic does not match the doctor profile.');
    }

    await _firestore
        .collection('doctorSchedules')
        .doc(doctorId)
        .set({
      ...schedule.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Checks whether the selected doctor has configured a schedule.
  Future<bool> hasSchedule() async {
    final schedule = await getMySchedule();
    return schedule != null;
  }
}
