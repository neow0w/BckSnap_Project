class StaffProfile {
  final String id;
  final String clinicId;
  final String name;
  final String role; // receptionist / doctor / pt
  final String professionalType;
  final String status; // active / pending / rejected / inactive
  final List<String> professions;
  final String salt;
  final String hash;
  final String? createdByName;
  final String? createdByRole;

  const StaffProfile({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.role,
    this.professionalType = 'Doctor',
    required this.status,
    required this.professions,
    required this.salt,
    required this.hash,
    this.createdByName,
    this.createdByRole,
  });

  bool get isDoctor => role == 'doctor';
  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  String get roleLabel => switch (role) {
    'doctor' => 'Doctor',
    'pt' => 'Physical Therapist',
    'receptionist' => 'Receptionist',
    _ => role,
  };

  String get statusLabel => switch (status) {
    'active' => 'Active',
    'pending' => 'Waiting for approval',
    'rejected' => 'Rejected',
    'inactive' => 'Inactive',
    _ => status,
  };

  factory StaffProfile.fromMap(String id, Map<String, dynamic> m) =>
      StaffProfile(
        id: id,
        clinicId: (m['clinicId'] ?? '') as String,
        name: (m['name'] ?? 'Unnamed') as String,
        role: (m['role'] ?? 'receptionist') as String,
        professionalType: (m['professionalType'] ?? 'Doctor') as String,
        status: (m['status'] ?? 'active') as String,
        professions: [
          for (final p in (m['professions'] as List? ?? const [])) p.toString(),
        ],
        salt: (m['passwordSalt'] ?? '') as String,
        hash: (m['passwordHash'] ?? '') as String,
        createdByName: m['createdByName'] as String?,
        createdByRole: m['createdByRole'] as String?,
      );
}
