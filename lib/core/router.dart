import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_screen.dart';
import '../features/admin/audit_log_screen.dart';
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
import '../features/screening/measurement_screen.dart';
import '../features/screening/person_info_screen.dart';
import '../features/screening/progress_screen.dart';
import '../features/screening/result_screen.dart';
import '../features/screening/screening_for_screen.dart';
import '../features/screening/screening_result.dart';
import '../features/screening/screening_steps_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/user/appointment_booking_screen.dart';
import '../features/user/appointments_screen.dart';
import '../features/user/consultation_screen.dart';
import '../features/user/clinic_details_screen.dart';
import '../features/user/clinic_discovery_screen.dart';
import '../features/user/home_screen.dart';
import '../features/user/message_screen.dart';
import '../features/user/messages_hub_screen.dart';
import '../features/user/patient_shell.dart';
import '../features/user/referral_screen.dart';
import '../features/web/staff_web_shell.dart';
import '../features/web/web_appointments_page.dart';
import '../features/web/web_messages_page.dart';
import '../features/web/web_patients_page.dart';
import '../services/auth_service.dart';
import 'home_for.dart';
import '../features/auth/verify_email_screen.dart';
import 'screen_placeholder.dart';
import '../features/web/web_doctor_schedule_page.dart';
import '../features/user/consultation_chat_screen.dart';
import '../features/user/notifications_screen.dart';
import '../features/auth/profile_picker_screen.dart';
import '../features/receptionist/doctor_profiles_screen.dart';
import '../features/auth/clinic_registration_screen.dart';
import '../features/developer/developer_clinics_page.dart';
import '../features/screening/questionnaire_screen.dart';

// Old imports of homeFor from this file keep working.
export 'home_for.dart' show homeFor;

// Screens that need a logged-in account.
const _protected = [
  '/home',
  '/referral',
  '/messages',
  '/clinics',
  '/appointments',
  '/consultation',
  '/consultation-chat',
  '/notifications',
  '/message',
  '/admin',
  '/reception',
  '/doctor',
  '/pt',
  '/profile',
  '/screening',
  '/progress',
  '/developer',
];

// Screens a logged-in user should never see again.
const _entryScreens = ['/', '/login', '/signup', '/reset', '/register-clinic'];

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
    case 'doctor':
    case 'pt':
      // Doctors and PTs share the existing staff appointment pages.
      // PTs additionally use their own /pt/schedule route.
      return _under(loc, '/doctor') ||
          _under(loc, '/pt') ||
          _under(loc, '/consultation') ||
          _under(loc, '/consultation-chat');

    case 'receptionist':
      return _under(loc, '/reception');

    case 'clinic_staff':
      return _under(loc, '/reception') ||
          _under(loc, '/doctor') ||
          _under(loc, '/consultation') ||
          _under(loc, '/consultation-chat');
    case 'developer':
      return _under(loc, '/developer');
    default:
      return _under(loc, '/home') ||
          _under(loc, '/referral') ||
          _under(loc, '/messages') ||
          _under(loc, '/clinics') ||
          _under(loc, '/appointments') ||
          _under(loc, '/consultation') ||
          _under(loc, '/consultation-chat') ||
          _under(loc, '/notifications') ||
          _under(loc, '/message') ||
          _under(loc, '/screening') ||
          _under(loc, '/progress');
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: kIsWeb ? '/login' : '/splash',
  // Runs before every navigation. AuthService is a singleton, so we read
  // the current user directly; screens call context.go() after login/logout,
  // which triggers this check.
  redirect: (context, state) {
    final auth = AuthService();
    final user = auth.currentUser;
    final loc = state.matchedLocation;

    // The website has no landing page or sign-up: staff log in.
    if (kIsWeb && (loc == '/' || loc == '/signup')) {
      return user == null ? '/login' : homeFor(user.role);
    }

    // Google/Facebook sign-in that still needs a date of birth and consent.
    if (user == null && auth.hasPendingSocial) {
      return (loc == '/complete-profile' || loc == '/privacy')
          ? null
          : '/complete-profile';
    }

    // Not logged in: sign up or log in first.
    if (user == null) {
      return _publicScreens.contains(loc) ? null : '/login';
    }

    // Patients must confirm their email before using the app.
    if (user.role == 'user' && !auth.isEmailVerified) {
      return (loc == '/verify-email' || loc == '/privacy' || loc == '/splash')
          ? null
          : '/verify-email';
    }
    if (loc == '/verify-email' || loc == '/complete-profile') {
      return homeFor(user.role);
    }

    // The shared clinic staff account must open a profile first.
    if (user.role == 'clinic_staff') {
      return (loc == '/profiles' || loc == '/privacy') ? null : '/profiles';
    }
    // Only a staff account can open the profile screen (to switch profile).
    if (loc == '/profiles') {
      return auth.isStaffAccount ? null : homeFor(user.role);
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

// ---- the website (receptionist, doctor and admin) -------------------------

final List<RouteBase> _webRoutes = [
  GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
  GoRoute(path: '/', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/signup', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
  GoRoute(path: '/privacy', builder: (c, s) => const PrivacyNoticeScreen()),
  GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
  GoRoute(path: '/profile/edit', builder: (c, s) => const EditProfileScreen()),
  GoRoute(path: '/profiles', builder: (c, s) => const ProfilePickerScreen()),
  GoRoute(
    path: '/register-clinic',
    builder: (c, s) => const ClinicRegistrationScreen(),
  ),
  GoRoute(path: '/developer', builder: (c, s) => const DeveloperClinicsPage()),
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
      GoRoute(
        path: '/reception/staff',
        builder: (c, s) => const DoctorProfilesScreen(embedded: true),
      ),
      // "embedded": the website shell already has the header and menu.
      GoRoute(
        path: '/admin',
        builder: (c, s) => const AdminScreen(embedded: true),
      ),
      GoRoute(
        path: '/admin/audit',
        builder: (c, s) => const AuditLogScreen(embedded: true),
      ),
      GoRoute(
        path: '/admin/clinic-location',
        builder: (c, s) => const ClinicLocationScreen(embedded: true),
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
      GoRoute(
        path: '/pt/schedule',
        builder: (c, s) => const WebDoctorSchedulePage(),
      ),
    ],
  ),
  // Consultation routes for the web portal.
  GoRoute(
    path: '/consultation-chat/:id',
    builder: (c, s) {
      return ConsultationChatScreen(appointmentId: s.pathParameters['id']!);
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

// ---- the phone app ---------------------------------------------------------

final List<RouteBase> _mobileRoutes = [
  // Splash, welcome, authentication
  GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
  GoRoute(path: '/', builder: (c, s) => const LandingScreen()),
  GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
  GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
  GoRoute(
    path: '/signup',
    builder: (c, s) => SignUpScreen(next: s.uri.queryParameters['next']),
  ),
  GoRoute(path: '/privacy', builder: (c, s) => const PrivacyNoticeScreen()),
  GoRoute(
    path: '/complete-profile',
    builder: (c, s) => const SignUpScreen(social: true),
  ),
  GoRoute(path: '/verify-email', builder: (c, s) => const VerifyEmailScreen()),
  // Screening: who for -> (person info) -> hub -> steps -> capture -> result
  GoRoute(
    path: '/screening/for',
    builder: (c, s) => const ScreeningForScreen(),
  ),
  GoRoute(
    path: '/screening/person',
    builder: (c, s) => const PersonInfoScreen(),
  ),
  GoRoute(
    path: '/screening/steps/:method',
    builder: (c, s) =>
        ScreeningStepsScreen(method: s.pathParameters['method']!),
  ),
  GoRoute(
    path: '/screening/questionnaire',
    builder: (c, s) => const QuestionnaireScreen(),
  ),
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
  GoRoute(path: '/profile/edit', builder: (c, s) => const EditProfileScreen()),
  GoRoute(path: '/profiles', builder: (c, s) => const ProfilePickerScreen()),
  GoRoute(
    path: '/reception/doctors',
    builder: (c, s) => const DoctorProfilesScreen(),
  ),

  // Bottom-bar tabs: Home, Referral, Messages, Profile (the centre button
  // opens the screening). The shell only draws the bar for patients.
  ShellRoute(
    builder: (context, state, child) =>
        PatientShell(location: state.matchedLocation, child: child),
    routes: [
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/referral', builder: (c, s) => const ReferralScreen()),
      GoRoute(path: '/messages', builder: (c, s) => const MessagesHubScreen()),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
    ],
  ),

  // Figure 8: user side (connector A)
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
      return ConsultationChatScreen(appointmentId: s.pathParameters['id']!);
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

  // Admin
  GoRoute(path: '/admin', builder: (c, s) => const AdminScreen()),
  GoRoute(path: '/admin/audit', builder: (c, s) => const AuditLogScreen()),
  GoRoute(
    path: '/admin/clinic-location',
    builder: (c, s) => const ClinicLocationScreen(),
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
