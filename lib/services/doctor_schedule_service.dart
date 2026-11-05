import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_schedule.dart';
import 'auth_service.dart';

class DoctorScheduleService {
  final FirebaseFirestore _firestore;

  DoctorScheduleService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// The doctor profile that is open (or the doctor's own account).
  String get doctorId {
    final u = AuthService().currentUser;
    if (u == null) {
      throw Exception('You must be logged in to manage your schedule.');
    }
    if (u.role != 'doctor') {
      throw Exception('Only doctor profiles can manage schedules.');
    }
    return u.profileId ?? u.id;
  }

  String get clinicId {
    final id = AuthService().currentUser?.clinicId;
    if (id == null || id.isEmpty) {
      throw Exception('Your account is not assigned to a clinic.');
    }
    return id;
  }

  Future<DoctorSchedule?> getMySchedule() async {
    final snapshot = await _firestore
        .collection('doctorSchedules')
        .doc(doctorId)
        .get();
    if (!snapshot.exists) return null;
    return DoctorSchedule.fromMap(snapshot.data()!);
  }

  Future<void> saveMySchedule(DoctorSchedule schedule) async {
    if (schedule.doctorId != doctorId) {
      throw Exception("You cannot save another doctor's schedule.");
    }
    if (schedule.clinicId != clinicId) {
      throw Exception('The schedule clinic does not match your account.');
    }
    await _firestore.collection('doctorSchedules').doc(doctorId).set({
      ...schedule.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasSchedule() async => (await getMySchedule()) != null;
}
