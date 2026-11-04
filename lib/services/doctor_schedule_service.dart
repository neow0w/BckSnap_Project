
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/doctor_schedule.dart';

class DoctorScheduleService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DoctorScheduleService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Gets the currently logged-in doctor's Firebase UID.
  String get _doctorId {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('You must be logged in to manage your schedule.');
    }

    return user.uid;
  }

  /// Loads the doctor's account information from the users collection.
  Future<DocumentSnapshot<Map<String, dynamic>>> _getDoctorAccount() async {
    final snapshot = await _firestore
        .collection('users')
        .doc(_doctorId)
        .get();

    if (!snapshot.exists) {
      throw Exception('Doctor account was not found.');
    }

    final data = snapshot.data()!;

    if (data['role'] != 'doctor') {
      throw Exception('Only doctor accounts can manage schedules.');
    }

    if (data['status'] != 'active') {
      throw Exception('Your doctor account is not active.');
    }

    return snapshot;
  }

  /// Loads the doctor's saved schedule.
  Future<DoctorSchedule?> getMySchedule() async {
    await _getDoctorAccount();

    final snapshot = await _firestore
        .collection('doctorSchedules')
        .doc(_doctorId)
        .get();

    if (!snapshot.exists) return null;

    return DoctorSchedule.fromMap(snapshot.data()!);
  }

  /// Saves or updates the doctor's weekly schedule.
  Future<void> saveMySchedule(DoctorSchedule schedule) async {
    final account = await _getDoctorAccount();
    final accountData = account.data()!;
    final clinicId = accountData['clinicId'] as String?;

    if (clinicId == null || clinicId.isEmpty) {
      throw Exception('Your doctor account is not assigned to a clinic.');
    }

    if (schedule.doctorId != _doctorId) {
      throw Exception('You cannot save another doctor\'s schedule.');
    }

    if (schedule.clinicId != clinicId) {
      throw Exception('The schedule clinic does not match your account.');
    }

    await _firestore
        .collection('doctorSchedules')
        .doc(_doctorId)
        .set({
          ...schedule.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Checks whether the logged-in doctor has configured a schedule.
  Future<bool> hasSchedule() async {
    final schedule = await getMySchedule();
    return schedule != null;
  }
}
