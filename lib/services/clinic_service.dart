import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' hide GeoPoint;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

import '../core/format.dart' show isPresentToday;
import 'api_client.dart';
import 'auth_service.dart';
import 'audit_log.dart';
import '../config/backend_config.dart';
import '../models/consultation_message.dart';

import 'dart:typed_data';

class GeoPoint {
  const GeoPoint({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class ClinicDoctor {
  const ClinicDoctor({
    required this.id,
    required this.userId,
    required this.name,
    required this.specializations,
    required this.professionalInfo,
    required this.supportsOnline,
    required this.supportsPhysical,
    this.professionalType,
    this.requiresReferral = false,
    this.isDemo = false,
    this.presentOn,
  });

  final String id;
  final String userId;
  final String? name;
  final List<String> specializations;
  final String? professionalInfo;
  final bool supportsOnline;
  final bool supportsPhysical;
  final String? professionalType;
  final bool requiresReferral;
  final bool isDemo;
  final String? presentOn;
  bool get isPresentToday => _isPresentToday(presentOn);

  factory ClinicDoctor.fromMap(String id, Map<String, dynamic> m) =>
      ClinicDoctor(
        id: id,
        userId: (m['userId'] as String?) ?? id,
        name: m['name'] as String?,
        specializations: [
          for (final s in (m['specializations'] as List? ?? const []))
            s.toString(),
        ],
        professionalInfo: m['professionalInfo'] as String?,
        professionalType: m['professionalType'] as String?,
        requiresReferral: m['requiresReferral'] as bool? ?? false,
        supportsOnline: m['supportsOnline'] as bool? ?? true,
        supportsPhysical: m['supportsPhysical'] as bool? ?? true,
        presentOn: m['presentOn'] as String?,
      );
}

bool _isPresentToday(String? presentOn) => isPresentToday(presentOn);

class ClinicDemoAppointmentType {
  const ClinicDemoAppointmentType({
    required this.mode,
    required this.name,
    required this.simulationOnly,
  });

  final String mode;
  final String name;
  final bool simulationOnly;
}

class ClinicInfo {
  const ClinicInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    required this.email,
    required this.timezone,
    required this.operatingHours,
    required this.supportsOnline,
    required this.supportsPhysical,
    this.demoOperatingHours = const {},
    this.demoAppointmentTypes = const [],
    required this.services,
    required this.doctors,
    required this.distanceKm,
  });

  final String id;
  final String name;
  final String? description;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final String timezone;
  final Map<String, dynamic> operatingHours;
  final bool supportsOnline;
  final bool supportsPhysical;
  final Map<String, dynamic> demoOperatingHours;
  final List<ClinicDemoAppointmentType> demoAppointmentTypes;
  final List<String> services;
  final List<ClinicDoctor> doctors;
  final double? distanceKm;

  bool get hasMapLocation =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  factory ClinicInfo.fromMap(
    String id,
    Map<String, dynamic> m, {
    List<ClinicDoctor> doctors = const [],
    double? distanceKm,
  }) => ClinicInfo(
    id: id,
    name: (m['name'] as String?) ?? 'Clinic',
    description: m['description'] as String?,
    address: (m['address'] as String?) ?? '',
    latitude: (m['latitude'] as num?)?.toDouble(),
    longitude: (m['longitude'] as num?)?.toDouble(),
    phone: m['phone'] as String?,
    email: m['email'] as String?,
    timezone: (m['timezone'] as String?) ?? 'Asia/Manila',
    operatingHours: Map<String, dynamic>.from(
      m['operatingHours'] as Map? ?? const {},
    ),
    supportsOnline: m['supportsOnline'] as bool? ?? false,
    supportsPhysical: m['supportsPhysical'] as bool? ?? false,
    services: [
      for (final s in (m['services'] as List? ?? const [])) s.toString(),
    ],
    doctors: doctors,
    distanceKm: distanceKm,
  );
}

class AppointmentSlot {
  const AppointmentSlot({
    required this.startsAt,
    required this.endsAt,
    required this.mode,
  });

  final DateTime startsAt;
  final DateTime endsAt;
  final String mode;
}

class ClinicAppointment {
  const ClinicAppointment({
    required this.id,
    required this.userId,
    required this.status,
    required this.mode,
    required this.scheduledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.clinicId,
    required this.clinicName,
    required this.clinicAddress,
    required this.doctorId,
    required this.doctorName,
    required this.reference,
    required this.cancellationReason,
    this.referralImageBytes,
    this.patientName,
    this.isDemo = false,
  });

  final String id;
  final String userId;
  final String? patientName;
  final String status;
  final String? mode;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? clinicId;
  final String? clinicName;
  final String? clinicAddress;
  final String? doctorId;
  final String? doctorName;
  final String? reference;
  final String? cancellationReason;
  final Uint8List? referralImageBytes;
  final bool isDemo;

  bool get canCancel =>
      (status == 'pending' || status == 'approved') &&
      scheduledAt != null &&
      scheduledAt!.difference(DateTime.now().toUtc()) >=
          const Duration(hours: 24);
}

class ClinicNotification {
  const ClinicNotification({
    required this.id,
    required this.appointmentId,
    required this.eventType,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String appointmentId;
  final String eventType;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
}

DateTime? _dt(dynamic v) => v is Timestamp ? v.toDate() : null;

class ClinicService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  static const _days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  // ---- helpers ----------------------------------------------------------

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

  static double _km(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static String _reference() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = math.Random.secure();
    return 'BCK-${List.generate(6, (_) => chars[r.nextInt(chars.length)]).join()}';
  }

  static DateTime _at(DateTime date, String hhmm) {
    final p = hhmm.split(':');
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.tryParse(p[0]) ?? 9,
      p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
    );
  }

  ClinicAppointment _appt(String id, Map<String, dynamic> m) {
    final created = _dt(m['createdAt']) ?? DateTime.now();
    final referralBlob = m['referralImage'] as Blob?;

    return ClinicAppointment(
      id: id,
      userId: (m['userId'] as String?) ?? '',
      patientName: m['patientName'] as String?,
      status: (m['status'] as String?) ?? 'pending',
      mode: m['mode'] as String?,
      scheduledAt: _dt(m['scheduledAt'])?.toUtc(),
      createdAt: created,
      updatedAt: _dt(m['updatedAt']) ?? created,
      clinicId: m['clinicId'] as String?,
      clinicName: m['clinicName'] as String?,
      clinicAddress: m['clinicAddress'] as String?,
      doctorId: m['doctorId'] as String?,
      doctorName: m['doctorName'] as String?,
      reference: m['reference'] as String?,
      referralImageBytes: referralBlob?.bytes,
      cancellationReason: m['cancellationReason'] as String?,
    );
  }

  bool _inState(ClinicAppointment a, String? state) {
    final now = DateTime.now().toUtc();
    final at = a.scheduledAt;
    switch (state) {
      case 'pending':
        return a.status == 'pending';
      case 'upcoming':
        return a.status == 'approved' && at != null && at.isAfter(now);
      case 'past':
        return at != null &&
            at.isBefore(now) &&
            (a.status == 'approved' || a.status == 'completed');
      case 'cancelled':
        return a.status == 'cancelled' ||
            a.status == 'rejected' ||
            a.status == 'declined';
      default:
        return true;
    }
  }

  // ---- clinics ----------------------------------------------------------

  /// Kept so the discovery screen needs no change.
  Future<void> checkHealth() async {}

  Future<List<ClinicInfo>> search({
    String? query,
    GeoPoint? location,
    double radiusKm = 50,
    String? service,
    String? mode,
  }) => _guard(() async {
    final snap = await _db.collection('clinics').get();
    final q = (query ?? '').trim().toLowerCase();
    final s = (service ?? '').trim().toLowerCase();
    final out = <ClinicInfo>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (q.isNotEmpty &&
          !((m['name'] as String?) ?? '').toLowerCase().contains(q)) {
        continue;
      }
      if (s.isNotEmpty &&
          !((m['services'] as List? ?? const []).any(
            (e) => e.toString().toLowerCase().contains(s),
          ))) {
        continue;
      }
      if (mode == 'physical' && m['supportsPhysical'] != true) continue;
      if (mode == 'online' && m['supportsOnline'] != true) continue;

      double? dist;
      if (location != null) {
        final lat = (m['latitude'] as num?)?.toDouble();
        final lon = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        dist = _km(location.latitude, location.longitude, lat, lon);
        if (dist > radiusKm) continue;
      }
      out.add(ClinicInfo.fromMap(d.id, m, distanceKm: dist));
    }
    out.sort(
      (a, b) => location != null
          ? (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0)
          : a.name.compareTo(b.name),
    );
    return out;
  });

  /// Place search through OpenStreetMap Nominatim (free, no key).
  Future<List<GeoPoint>> geocode(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query.trim(),
        'format': 'jsonv2',
        'limit': '5',
      });
      final res = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              if (!kIsWeb) 'User-Agent': 'flutter_bcksnap/1.0',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw ApiException(
          res.statusCode,
          'Location search failed. Please try again.',
        );
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      return [
        for (final item in data.whereType<Map>())
          GeoPoint(
            label: item['display_name'] as String,
            latitude: double.parse(item['lat'] as String),
            longitude: double.parse(item['lon'] as String),
          ),
      ];
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the location service. Check your connection.',
      );
    }
  }

  /// Admin: saves the pin for their own clinic.
  Future<void> updateClinicLocation(double latitude, double longitude) =>
      _guard(() async {
        final clinicId = _me.clinicId;
        if (clinicId == null) {
          throw ApiException(403, 'No clinic is assigned to this account.');
        }
        final batch = _db.batch();
        batch.update(_db.collection('clinics').doc(clinicId), {
          'latitude': latitude,
          'longitude': longitude,
        });
        AuditLog.addTo(
          batch,
          action: 'clinic.location_updated',
          targetType: 'clinic',
          targetId: clinicId,
          details:
              '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
        );
        await batch.commit();
      });

  Future<ClinicInfo> clinic(String id) => _guard(() async {
    final snap = await _db.collection('clinics').doc(id).get();
    final data = snap.data();
    if (data == null) throw ApiException(404, 'Clinic not found.');
    final docs = await _db
        .collection('doctors')
        .where('clinicId', isEqualTo: id)
        .where('active', isEqualTo: true)
        .get();
    return ClinicInfo.fromMap(
      snap.id,
      data,
      doctors: [
        for (final d in docs.docs) ClinicDoctor.fromMap(d.id, d.data()),
      ],
    );
  });

  Stream<String?> doctorPresentOnStream(String doctorId) => _db
      .collection('doctors')
      .doc(doctorId)
      .snapshots()
      .map((s) => s.data()?['presentOn'] as String?);

  // ---- slots and booking --------------------------------------------------

  /// Half-hour slots inside the clinic's operating hours, minus booked ones.
  /// With no hours saved on the clinic, Mon-Fri 09:00-17:00 is used.

  /// Generates appointment slots based on the doctor's weekly schedule.
  /// Each consultation lasts 60 minutes, followed by a 10-minute buffer.

  /// Generates appointment slots based on the doctor's weekly schedule.
  /// Each consultation lasts 60 minutes, followed by a 10-minute buffer.

  /// Generates appointment slots using the doctor's weekly schedule.
  /// Normal slots are hourly. A 10-minute buffer is added after booked
  /// appointments before the next available appointment.
  Future<List<AppointmentSlot>> slots({
    required String clinicId,
    required String doctorId,
    required DateTime date,
    required String mode,
  }) => _guard(() async {
    // Get the doctor's saved weekly schedule.
    final scheduleSnap = await _db
        .collection('doctorSchedules')
        .doc(doctorId)
        .get();

    if (!scheduleSnap.exists) {
      return <AppointmentSlot>[];
    }

    final scheduleData = scheduleSnap.data()!;

    final weeklySchedule = Map<String, dynamic>.from(
      scheduleData['weeklySchedule'] as Map? ?? {},
    );

    final dayName = _days[date.weekday - 1];
    final dayData = weeklySchedule[dayName];

    if (dayData is! Map || dayData['enabled'] != true) {
      return <AppointmentSlot>[];
    }

    final day = Map<String, dynamic>.from(dayData);

    final startTime = _at(date, day['timeIn']?.toString() ?? '08:00');

    final endTime = _at(date, day['timeOut']?.toString() ?? '17:00');

    // Lunch break.
    DateTime? lunchStart;
    DateTime? lunchEnd;

    if (day['lunchBreakEnabled'] == true) {
      lunchStart = _at(date, day['lunchStart']?.toString() ?? '12:00');

      lunchEnd = _at(date, day['lunchEnd']?.toString() ?? '13:00');
    }

    // Appointment duration and buffer.
    final appointmentDuration = Duration(
      minutes: scheduleData['appointmentDuration'] as int? ?? 60,
    );

    final breakDuration = Duration(
      minutes: scheduleData['breakDuration'] as int? ?? 10,
    );

    // Retrieve the doctor's existing bookings.
    final bookedSnap = await _db
        .collection('bookedSlots')
        .where('doctorId', isEqualTo: doctorId)
        .get();

    final bookedIntervals = <({DateTime start, DateTime end})>[];

    for (final doc in bookedSnap.docs) {
      final data = doc.data();

      final bookedStart = (data['startsAt'] as Timestamp).toDate();

      if (bookedStart.year == date.year &&
          bookedStart.month == date.month &&
          bookedStart.day == date.day) {
        bookedIntervals.add((
          start: bookedStart,
          end: bookedStart.add(appointmentDuration),
        ));
      }
    }

    final now = DateTime.now();
    final slots = <AppointmentSlot>[];

    var current = startTime;

    while (!current.add(appointmentDuration).isAfter(endTime)) {
      final appointmentEnd = current.add(appointmentDuration);

      // If the appointment overlaps lunch, resume after lunch.
      if (lunchStart != null &&
          lunchEnd != null &&
          current.isBefore(lunchEnd) &&
          appointmentEnd.isAfter(lunchStart)) {
        current = lunchEnd;
        continue;
      }

      // Check whether this appointment overlaps an existing booking.
      final overlappingBookings = bookedIntervals.where(
        (booking) =>
            current.isBefore(booking.end) &&
            appointmentEnd.isAfter(booking.start),
      );

      if (overlappingBookings.isNotEmpty) {
        // Resume 10 minutes after the latest overlapping booking.
        DateTime latestEnd = overlappingBookings.first.end;

        for (final booking in overlappingBookings) {
          if (booking.end.isAfter(latestEnd)) {
            latestEnd = booking.end;
          }
        }

        current = latestEnd.add(breakDuration);
        continue;
      }

      // Only show future appointment slots.
      if (current.isAfter(now)) {
        slots.add(
          AppointmentSlot(
            startsAt: current,
            endsAt: appointmentEnd,
            mode: mode,
          ),
        );
      }

      // Normal availability advances by one hour.
      current = current.add(appointmentDuration);
    }

    return slots;
  });

  Future<ClinicAppointment> book({
    required String clinicId,
    required String doctorId,
    required String mode,
    required DateTime startsAt,
    Uint8List? referralImageBytes,
  }) => _guard(() async {
    final me = _me;
    final clinicSnap = await _db.collection('clinics').doc(clinicId).get();
    final doctorSnap = await _db.collection('doctors').doc(doctorId).get();
    final clinic = clinicSnap.data() ?? {};

    final ref = _db.collection('appointments').doc();
    // One document per doctor and time: a second booking of the same time
    // is refused by the security rules, so nobody can double-book.
    final slotId = '${doctorId}_${startsAt.millisecondsSinceEpoch}';
    final batch = _db.batch();
    final reference = _reference();
    AuditLog.addTo(
      batch,
      action: 'appointment.booked',
      clinicId: clinicId,
      targetType: 'appointment',
      targetId: ref.id,
      targetName: reference,
      details: '${doctorSnap.data()?['name'] ?? 'doctor'}, $mode',
    );
    batch.set(_db.collection('bookedSlots').doc(slotId), {
      'doctorId': doctorId,
      'clinicId': clinicId,
      'userId': me.id,
      'appointmentId': ref.id,
      'startsAt': Timestamp.fromDate(startsAt),
    });
    batch.set(ref, {
      'userId': me.id,
      'patientName': me.displayName ?? 'Patient',
      'clinicId': clinicId,
      'clinicName': clinic['name'],
      'clinicAddress': clinic['address'],
      'doctorId': doctorId,
      'doctorName': doctorSnap.data()?['name'],
      'mode': mode,
      'isDemo': doctorSnap.data()?['isDemo'] == true,
      'scheduledAt': Timestamp.fromDate(startsAt),
      'status': 'pending',
      'reference': reference,
      'slotId': slotId,
      'cancellationReason': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (referralImageBytes != null) 'referralImage': Blob(referralImageBytes),
    });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw ApiException(
          409,
          'That time was just taken. Please choose another.',
        );
      }
      rethrow;
    }
    final saved = await ref.get();

    // Notify clinic staff about the successful booking.
    // Notify clinic staff about the successful booking.
    try {
      debugPrint('[BOOKING NOTIFICATION] Appointment saved: ${ref.id}');

      debugPrint('[BOOKING NOTIFICATION] Requesting Firebase ID token...');
      final token = await _auth.getFirebaseIdToken();

      debugPrint('[BOOKING NOTIFICATION] Firebase ID token obtained.');

      final url = '${BackendConfig.baseUrl}/api/appointments/notify-booking';

      debugPrint('[BOOKING NOTIFICATION] Sending request to: $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'appointmentId': ref.id}),
          )
          .timeout(const Duration(seconds: 20));

      debugPrint(
        '[BOOKING NOTIFICATION] Response: '
        '${response.statusCode} ${response.body}',
      );
    } catch (error, stackTrace) {
      debugPrint('[BOOKING NOTIFICATION] FAILED: $error');
      debugPrint('[BOOKING NOTIFICATION] STACK TRACE: $stackTrace');
    }

    return _appt(saved.id, saved.data()!);
  });

  Future<List<ClinicAppointment>> appointments({String? state}) =>
      _guard(() async {
        final snap = await _db
            .collection('appointments')
            .where('userId', isEqualTo: _me.id)
            .get();
        final list = [for (final d in snap.docs) _appt(d.id, d.data())]
            .where((a) => _inState(a, state))
            .toList();
        list.sort(
          (a, b) => (b.scheduledAt ?? b.createdAt).compareTo(
            a.scheduledAt ?? a.createdAt,
          ),
        );
        return list;
      });

  Future<ClinicAppointment> appointment(String id) => _guard(() async {
    final snap = await _db.collection('appointments').doc(id).get();
    final data = snap.data();
    if (data == null) throw ApiException(404, 'Appointment not found.');
    return _appt(snap.id, data);
  });

  Future<ClinicAppointment> cancel(String id, String reason) =>
      _guard(() async {
        final ref = _db.collection('appointments').doc(id);
        final snap = await ref.get();
        final slotId = snap.data()?['slotId'] as String?;
        final batch = _db.batch();
        AuditLog.addTo(
          batch,
          action: 'appointment.cancelled',
          clinicId: snap.data()?['clinicId'] as String?,
          targetType: 'appointment',
          targetId: id,
          targetName: snap.data()?['reference'] as String?,
          details: reason.trim(),
        );
        batch.update(ref, {
          'status': 'cancelled',
          'cancellationReason': reason.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (slotId != null) {
          batch.delete(_db.collection('bookedSlots').doc(slotId));
        }
        await batch.commit();
        final saved = await ref.get();
        return _appt(saved.id, saved.data()!);
      });

  /// Free video room (Jitsi Meet), named after the appointment reference.

  /// LiveKit video room: requests secure consultation credentials from the backend.
  Future<Map<String, dynamic>> consultation(String id) async {
    final a = await appointment(id);

    if (a.status != 'approved' || a.mode != 'online') {
      throw ApiException(
        409,
        'The consultation is only available for approved online appointments.',
      );
    }

    try {
      final authToken =
          _auth.profileSessionToken ?? await _auth.getFirebaseIdToken();

      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/consultation/token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'appointmentId': id}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // The server did not return valid JSON.
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode,
          (data['error'] as String?) ??
              'Unable to join the consultation. Please try again.',
        );
      }

      if (data['serverUrl'] == null ||
          data['roomName'] == null ||
          data['token'] == null) {
        throw ApiException(
          500,
          'The server returned incomplete consultation details.',
        );
      }

      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  /// Doctor: marks an approved appointment as completed.
  Future<void> completeAppointment(String appointmentId) async {
    final me = _auth.currentUser;

    if (me == null || me.role != 'doctor') {
      throw ApiException(
        403,
        'Only the assigned doctor can complete this appointment.',
      );
    }

    final token = _auth.profileSessionToken;

    if (token == null || token.isEmpty) {
      throw ApiException(
        401,
        'Your doctor session has expired. Please select your profile again.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/appointments/complete'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'appointmentId': appointmentId}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // The server did not return valid JSON.
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          (data['error'] as String?) ??
              'Unable to complete the appointment. Please try again.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  /// Doctor: permanently ends the online consultation for both participants.
  /// The backend independently verifies that the caller is the assigned doctor.
  Future<void> endConsultation(String appointmentId) async {
    try {
      final profileToken = _auth.profileSessionToken;

      if (profileToken == null || profileToken.isEmpty) {
        throw ApiException(401, 'Please sign in to your doctor profile again.');
      }

      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/consultation/end'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $profileToken',
            },
            body: jsonEncode({'appointmentId': appointmentId}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // The server did not return a valid JSON response.
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          (data['error'] as String?) ??
              (data['message'] as String?) ??
              'Unable to end the consultation. Please try again.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  Future<void> startInstantMeeting(String appointmentId) async {
    try {
      final profileToken = _auth.profileSessionToken;

      if (profileToken == null || profileToken.isEmpty) {
        throw ApiException(401, 'Please sign in to your doctor profile again.');
      }

      final response = await http
          .post(
            Uri.parse(
              '${BackendConfig.baseUrl}/api/consultation/start-instant',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $profileToken',
            },
            body: jsonEncode({'appointmentId': appointmentId}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // The server did not return valid JSON.
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          (data['error'] as String?) ??
              (data['message'] as String?) ??
              'Unable to start the instant meeting.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    }
  }

  // ---- notifications ------------------------------------------------------

  Future<List<ClinicNotification>> notifications({bool unreadOnly = false}) =>
      _guard(() async {
        final snap = await _db
            .collection('notifications')
            .where('userId', isEqualTo: _me.id)
            .get();
        final list = [
          for (final d in snap.docs)
            ClinicNotification(
              id: d.id,
              appointmentId: (d.data()['appointmentId'] as String?) ?? '',
              eventType: (d.data()['eventType'] as String?) ?? '',
              title: (d.data()['title'] as String?) ?? '',
              message: (d.data()['message'] as String?) ?? '',
              createdAt: _dt(d.data()['createdAt']) ?? DateTime.now(),
              isRead: d.data()['read'] == true,
            ),
        ].where((n) => !unreadOnly || !n.isRead).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<void> markNotificationRead(String id) => _guard(
    () => _db.collection('notifications').doc(id).update({'read': true}),
  );

  // ---- staff ------------------------------------------------------------

  /// Receptionist: all requests of the clinic. Doctor: only their own.
  Future<List<ClinicAppointment>> staffAppointments({String? state}) =>
      _guard(() async {
        final me = _me;
        Query<Map<String, dynamic>> q = _db
            .collection('appointments')
            .where('clinicId', isEqualTo: me.clinicId);
        if (me.role == 'doctor') {
          q = q.where('doctorId', isEqualTo: me.profileId ?? me.id);
        }
        final snap = await q.get();
        final list = [for (final d in snap.docs) _appt(d.id, d.data())]
            .where((a) => _inState(a, state))
            .toList();
        list.sort(
          (a, b) => (a.scheduledAt ?? a.createdAt).compareTo(
            b.scheduledAt ?? b.createdAt,
          ),
        );
        return list;
      });

  Future<void> reviewAppointment(String id, {required bool approve}) =>
      _guard(() async {
        final me = _me;
        final ref = _db.collection('appointments').doc(id);
        final snap = await ref.get();
        final data = snap.data();
        if (data == null) throw ApiException(404, 'Appointment not found.');
        final batch = _db.batch();
        AuditLog.addTo(
          batch,
          action: approve ? 'appointment.approved' : 'appointment.rejected',
          targetType: 'appointment',
          targetId: id,
          targetName: data['reference'] as String?,
          details: 'Patient: ${data['patientName'] ?? ''}',
        );
        batch.update(ref, {
          'status': approve ? 'approved' : 'rejected',
          'reviewedBy': me.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batch.set(_db.collection('notifications').doc(), {
          'userId': data['userId'],
          'appointmentId': id,
          'eventType': approve ? 'approved' : 'rejected',
          'title': approve ? 'Appointment approved' : 'Appointment rejected',
          'message':
              'Your appointment ${data['reference']} was '
              '${approve ? 'approved' : 'rejected'} by the clinic.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        final slotId = data['slotId'] as String?;
        if (!approve && slotId != null) {
          batch.delete(_db.collection('bookedSlots').doc(slotId));
        }
        await batch.commit();
      });

  /// Live list for the website: receptionist = whole clinic, doctor = own.
  Stream<List<ClinicAppointment>> staffAppointmentsStream() {
    final me = _me;
    Query<Map<String, dynamic>> q = _db
        .collection('appointments')
        .where('clinicId', isEqualTo: me.clinicId);
    if (me.role == 'doctor') {
      q = q.where('doctorId', isEqualTo: me.profileId ?? me.id);
    }
    return q.snapshots().map((snap) {
      final list = [for (final d in snap.docs) _appt(d.id, d.data())];
      list.sort(
        (a, b) => (a.scheduledAt ?? a.createdAt).compareTo(
          b.scheduledAt ?? b.createdAt,
        ),
      );
      return list;
    });
  }

  /// The receptionists and doctors of the clinic (read-only).
  Future<List<Map<String, dynamic>>> staffList() => _guard(() async {
    final snap = await _db
        .collection('users')
        .where('clinicId', isEqualTo: _me.clinicId)
        .get();
    final list = [
      for (final d in snap.docs)
        if (d.data()['role'] == 'doctor' || d.data()['role'] == 'receptionist')
          {
            'id': d.id,
            'name': d.data()['name'],
            'email': d.data()['email'],
            'role': d.data()['role'],
            'status': d.data()['status'] ?? 'active',
            'professions': d.data()['professions'] ?? const [],
          },
    ];
    list.sort(
      (a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
    );
    return list;
  });

  /// Admin: activate or deactivate a staff account.
  Future<void> setStaffActive(
    String id,
    String role,
    bool active,
    String name,
  ) => _guard(() async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(id), {
      'status': active ? 'active' : 'inactive',
    });
    // A doctor is only bookable by patients while active.
    if (role == 'doctor') {
      batch.update(_db.collection('doctors').doc(id), {'active': active});
    }
    AuditLog.addTo(
      batch,
      action: active ? 'staff.activated' : 'staff.deactivated',
      targetType: 'user',
      targetId: id,
      targetName: name,
      details: role,
    );
    await batch.commit();
  });

  /// Admin: the latest audit log entries of the clinic.
  /// Uses the fast ordered query. If the database index does not exist yet,
  /// it reads the clinic's entries and sorts them here instead.
  Future<List<Map<String, dynamic>>> auditLogs() => _guard(() async {
    final base = _db
        .collection('auditLogs')
        .where('clinicId', isEqualTo: _me.clinicId);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await base.orderBy('createdAt', descending: true).limit(300).get();
    } on FirebaseException catch (e) {
      if (e.code != 'failed-precondition') rethrow;
      snap = await base.get();
    }
    final list = [
      for (final d in snap.docs)
        {...d.data(), 'id': d.id, 'createdAt': _dt(d.data()['createdAt'])},
    ];
    list.sort(
      (a, b) => ((b['createdAt'] as DateTime?) ?? DateTime(2000)).compareTo(
        (a['createdAt'] as DateTime?) ?? DateTime(2000),
      ),
    );
    return list.take(300).toList();
  });

  // ---- consultation chat -----------------------------------------------

  /// Retrieves messages through the backend using the patient's or
  /// doctor's appropriate authentication token.
  Future<List<ConsultationMessage>> _getConsultationMessages(
    String appointmentId,
  ) async {
    try {
      final authToken =
          _auth.profileSessionToken ?? await _auth.getFirebaseIdToken();

      final uri = Uri.parse(
        '${BackendConfig.baseUrl}/api/consultation/messages',
      ).replace(queryParameters: {'appointmentId': appointmentId});

      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $authToken',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          data['error'] as String? ?? 'Unable to load consultation messages.',
        );
      }

      final messages = data['messages'] as List? ?? [];

      return messages
          .whereType<Map>()
          .map(
            (message) => ConsultationMessage.fromJson(
              Map<String, dynamic>.from(message),
            ),
          )
          .toList();
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot load messages. Please check your internet connection.',
      );
    }
  }

  /// Refreshes the message list every three seconds.
  Stream<List<ConsultationMessage>> consultationMessages(
    String appointmentId,
  ) async* {
    while (true) {
      yield await _getConsultationMessages(appointmentId);
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  /// Sends a message through the authenticated backend endpoint.
  Future<void> sendConsultationMessage(
    String appointmentId,
    String text,
  ) async {
    final message = text.trim();

    if (message.isEmpty) {
      throw ApiException(422, 'Message cannot be empty.');
    }

    if (message.length > 4000) {
      throw ApiException(422, 'Message cannot exceed 4000 characters.');
    }

    try {
      final authToken =
          _auth.profileSessionToken ?? await _auth.getFirebaseIdToken();

      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/consultation/messages'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'appointmentId': appointmentId, 'text': message}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        // The server did not return valid JSON.
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          data['error'] as String? ?? 'Unable to send your message.',
        );
      }
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot send your message. Please check your internet connection.',
      );
    }
  }
}

String appointmentStatusLabel(String status) => switch (status) {
  'pending' => 'Pending',
  'approved' => 'Approved',
  'rejected' || 'declined' => 'Rejected',
  'cancelled' => 'Cancelled',
  'completed' => 'Completed',
  _ => status,
};
