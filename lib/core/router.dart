import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../features/auth/edit_profile_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/privacy_notice.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/receptionist/clinic_location_screen.dart';
import '../features/receptionist/inbox_screen.dart';
import '../features/receptionist/patient_chat_screen.dart';
import '../features/receptionist/staff_appointments_screen.dart';
import '../features/screening/camera_capture_screen.dart';
import '../features/screening/photo_screen.dart';
import '../features/screening/progress_screen.dart';
import '../features/screening/result_screen.dart';
import '../features/screening/measurement_screen.dart';
import '../features/user/appointment_booking_screen.dart';
import '../features/user/appointments_screen.dart';
import '../features/user/consultation_screen.dart';
import '../features/user/clinic_details_screen.dart';
import '../features/user/clinic_discovery_screen.dart';
import '../features/user/home_screen.dart';
import '../features/user/message_screen.dart';
import '../features/web/staff_web_shell.dart';
import '../features/web/web_appointments_page.dart';
import '../features/web/web_messages_page.dart';
import '../features/web/web_patients_page.dart';
import '../services/auth_service.dart';
import 'screen_placeholder.dart';
import '../features/screening/screening_result.dart';
import '../features/splash/splash_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/admin/audit_log_screen.dart';
import '../features/screening/person_info_screen.dart';
import '../features/screening/screening_for_screen.dart';
import '../features/web/web_doctor_schedule_page.dart';
import '../features/user/consultation_chat_screen.dart';

/// Where each role lands after login (connectors A, B, C in the SFD).
String homeFor(String role) {
  switch (role) {
    case 'admin':
      return '/admin';
    case 'receptionist':
      return '/reception'; // connector B
    case 'doctor':
      return '/doctor'; // connector C
    default:
      return '/home'; // connector A
  }
}

// Screens that need a logged-in account.
const _protected = [
  '/home',
  '/clinics',
  '/appointments',
  '/consultation',
  '/notifications',
  '/message',
  '/admin',
  '/reception',
  '/doctor',
  '/profile',
  '/screening',
  '/progress',
];

// Screens a logged-in user should never see again.
const _entryScreens = ['/', '/login', '/signup', '/reset'];

// Everything a visitor who is not logged in may open.
const _publicScreens = [..._entryScreens, '/privacy', '/splash'];

bool _under(String loc, String prefix) =>
    loc == prefix || loc.startsWith('$prefix/');

/// Which protected screens each role may open.
bool _roleAllowed(String role, String loc) {
  if (_under(loc, '/profile')) return true;
  switch (role) {
    case 'admin':
      return _under(loc, '/admin');
    case 'receptionist':
      return _under(loc, '/reception');
    case 'doctor':
      return _under(loc, '/doctor') ||
          _under(loc, '/consultation');
    default:
      return _under(loc, '/home') ||
          _under(loc, '/clinics') ||
          _under(loc, '/appointments') ||
          _under(loc, '/consultation') ||
          _under(loc, '/notifications') ||
          _under(loc, '/message') ||
          _under(loc, '/screening') ||
          _under(loc, '/progress');
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  // Runs before every navigation. AuthService is a singleton, so we read
  // the current user directly; screens call context.go() after login/logout,
  // which triggers this check.
  redirect: (context, state) {
    final user = AuthService().currentUser;
    final loc = state.matchedLocation;

    // The website has no landing page or sign-up: staff log in.
    if (kIsWeb && (loc == '/' || loc == '/signup')) {
      return user == null ? '/login' : homeFor(user.role);
    }

    // Not logged in: sign up or log in first.
    if (user == null) {
      return _publicScreens.contains(loc) ? null : '/login';
    }

    if (_entryScreens.contains(loc)) return homeFor(user.role);

    final isProtected = _protected.any((p) => _under(loc, p));
    if (isProtected && !_roleAllowed(user.role, loc)) {
      return homeFor(user.role);
    }
    return null;
  },

  routes: kIsWeb ? _webRoutes : _mobileRoutes,
  errorBuilder: (context, state) => const _GoHome(),
);

// ---- the website (receptionist and doctor only) --------------------------------

final List<RouteBase> _webRoutes = [
  GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
  GoRoute(path: '/', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/signup', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
  GoRoute(path: '/privacy', builder: (c, s) => const PrivacyNoticeScreen()),
  GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
  GoRoute(path: '/profile/edit', builder: (c, s) => const EditProfileScreen()),
  ShellRoute(
    builder: (context, state, child) =>
        StaffWebShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(
        path: '/reception',
        builder: (c, s) => const WebAppointmentsPage(isReception: true),
      ),
      GoRoute(
        path: '/reception/inbox',
        builder: (c, s) => const WebMessagesPage(),
      ),
      GoRoute(path: '/admin', builder: (c, s) => const AdminScreen()),
      GoRoute(path: '/admin/audit', builder: (c, s) => const AuditLogScreen()),
      GoRoute(
        path: '/admin/clinic-location',
        builder: (c, s) => const ClinicLocationScreen(),
      ),
      GoRoute(
        path: '/doctor',
        builder: (c, s) => const WebAppointmentsPage(isReception: false),
      ),
      GoRoute(
        path: '/doctor/patients',
        builder: (c, s) => const WebPatientsPage(),
      ),
      GoRoute(
        path: '/doctor/schedule',
        builder: (c, s) => const WebDoctorSchedulePage(),
      ),
        ],
      ),// Consultation routes for the web portal.
  GoRoute(
    path: '/consultation-chat/:id',
    builder: (c, s) {
      return ConsultationChatScreen(
        appointmentId: s.pathParameters['id']!,
      );
    },
  ),
  GoRoute(
    path: '/consultation/:id',
    builder: (c, s) {
      final credentials = s.extra as Map<String, dynamic>;

      return ConsultationScreen(
        appointmentId: s.pathParameters['id']!,
        credentials: credentials,
      );
    },
  ),
];

// ---- the phone app ------------------------------------------------------------

final List<RouteBase> _mobileRoutes = [
  // Figure 7: landing, login, sign-up, reset, screening
  GoRoute(path: '/', builder: (c, s) => const LandingScreen()),
  GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
  GoRoute(
    path: '/signup',
    builder: (c, s) => SignUpScreen(next: s.uri.queryParameters['next']),
  ),
  GoRoute(path: '/privacy', builder: (c, s) => const PrivacyNoticeScreen()),
  GoRoute(
    path: '/screening/for',
    builder: (c, s) => const ScreeningForScreen(),
  ),
  GoRoute(
    path: '/screening/person',
    builder: (c, s) => const PersonInfoScreen(),
  ),
  GoRoute(
    path: '/screening/photo',
    builder: (c, s) => const CameraCaptureScreen(),
  ),
  GoRoute(path: '/screening/upload', builder: (c, s) => const PhotoScreen()),
  GoRoute(
    path: '/screening/test',
    builder: (c, s) => const MeasurementScreen(),
  ),
  GoRoute(
    path: '/screening/result',
    builder: (c, s) {
      final e = s.extra;
      final data = e is ResultData
          ? e
          : ResultData.fromAtr(e is double ? e : 0.0);
      return ResultScreen(data: data);
    },
  ),
  GoRoute(path: '/progress', builder: (c, s) => const ProgressScreen()),

  // Profile (all roles)
  GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
  GoRoute(path: '/profile/edit', builder: (c, s) => const EditProfileScreen()),

  // Figure 8: user side (connector A)
  GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
  GoRoute(path: '/clinics', builder: (c, s) => const ClinicDiscoveryScreen()),
  GoRoute(
    path: '/clinics/:id',
    builder: (c, s) => ClinicDetailsScreen(clinicId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/clinics/:id/book',
    builder: (c, s) =>
        AppointmentBookingScreen(clinicId: s.pathParameters['id']!),
  ),
  GoRoute(path: '/appointments', builder: (c, s) => const AppointmentsScreen()),
  GoRoute(
    path: '/appointments/:id',
    builder: (c, s) =>
        AppointmentDetailsScreen(appointmentId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/consultation/:id',
    builder: (c, s) {
      final credentials = s.extra as Map<String, dynamic>;

      return ConsultationScreen(
        appointmentId: s.pathParameters['id']!,
        credentials: credentials,
      );
    },
  ),
  GoRoute(
    path: '/consultation-chat/:id',
    builder: (c, s) {
        return ConsultationChatScreen(
            appointmentId: s.pathParameters['id']!,
        );
    },
  ),

  GoRoute(
    path: '/notifications',
    builder: (c, s) => const NotificationsScreen(),
  ),
  GoRoute(
    path: '/message/:clinicId',
    builder: (c, s) => MessageScreen(clinicId: s.pathParameters['clinicId']!),
  ),

  // Figure 9: receptionist (connector B)
  GoRoute(
    path: '/reception',
    builder: (c, s) => const StaffAppointmentsScreen(isReception: true),
  ),
  GoRoute(path: '/reception/inbox', builder: (c, s) => const InboxScreen()),
  GoRoute(path: '/admin', builder: (c, s) => const AdminScreen()),
  GoRoute(path: '/admin/audit', builder: (c, s) => const AuditLogScreen()),
  GoRoute(
    path: '/admin/clinic-location',
    builder: (c, s) => const ClinicLocationScreen(),
  ),
  GoRoute(
    path: '/reception/chat/:patientId',
    builder: (c, s) {
      final clinicId = AuthService().currentUser?.clinicId;
      if (clinicId == null) {
        throw StateError('The logged-in receptionist has no clinic assigned.');
      }
      return PatientChatScreen(
        patientId: s.pathParameters['patientId']!,
        clinicId: clinicId,
        patientName: s.extra is String ? s.extra as String : null,
      );
    },
  ),

  // Figure 10: doctor (connector C)
  GoRoute(
    path: '/doctor',
    builder: (c, s) => const StaffAppointmentsScreen(isReception: false),
  ),
  GoRoute(
    path: '/doctor/patient',
    builder: (c, s) => const PlaceholderScreen('Patient Profile'),
  ),
];

/// Unknown address: go back to the start, which redirects to the right page.
class _GoHome extends StatefulWidget {
  const _GoHome();

  @override
  State<_GoHome> createState() => _GoHomeState();
}

class _GoHomeState extends State<_GoHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
