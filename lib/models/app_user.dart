import '../core/validators.dart';

class AppUser {
  final String
  id; // the Firebase Auth uid (the shared account for clinic staff)
  final String? clinicId;
  final String? name;
  final String? email;
  final String role; // user / receptionist / doctor / admin / clinic_staff
  final String status; // active / pending / rejected
  final String? phone;
  final DateTime? dateOfBirth;
  final String? address;
  final bool hasPhoto;

  /// Set when the clinic staff account has opened a profile.
  final String? profileId;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.status = 'active',
    this.clinicId,
    this.phone,
    this.dateOfBirth,
    this.address,
    this.hasPhoto = false,
    this.profileId,
  });

  /// The same account acting as one of its profiles.
  AppUser copyWith({String? name, String? role, String? profileId}) => AppUser(
    id: id,
    clinicId: clinicId,
    name: name ?? this.name,
    email: email,
    role: role ?? this.role,
    status: status,
    phone: phone,
    dateOfBirth: dateOfBirth,
    address: address,
    hasPhoto: hasPhoto,
    profileId: profileId ?? this.profileId,
  );

  String? get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = email?.trim();
    return (e != null && e.isNotEmpty) ? e : null;
  }

  int? get age => dateOfBirth == null
      ? null
      : Validators.ageOn(dateOfBirth!, DateTime.now());

  factory AppUser.fromMap(String id, Map<String, dynamic> m) {
    final dob = m['dateOfBirth'];
    return AppUser(
      id: id,
      clinicId: m['clinicId'] as String?,
      name: m['name'] as String?,
      email: m['email'] as String?,
      role: (m['role'] as String?) ?? 'user',
      status: (m['status'] as String?) ?? 'active',
      phone: m['phone'] as String?,
      dateOfBirth: dob is String ? DateTime.tryParse(dob) : null,
      address: m['address'] as String?,
      hasPhoto: m['hasPhoto'] == true,
    );
  }
}
