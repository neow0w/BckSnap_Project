/// Where each role lands after login (connectors A, B, C in the SFD).
String homeFor(String role) {
  switch (role) {
    case 'admin':
      return '/admin';
    case 'receptionist':
      return '/reception';
    case 'pt':
      return '/doctor';
    case 'doctor':
      return '/doctor';
    case 'clinic_staff':
      return '/profiles';
    case 'developer':
      return '/developer';
    default:
      return '/home';
  }
}
