import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/format.dart';
import '../core/image_compress.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'audit_log.dart';
import '../models/staff_profile.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class AuthService {
  // One shared instance, so every screen sees the same logged-in user.
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final FirebaseAuth _fa = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AppUser? _account; // the Firebase account's own record
  StaffProfile? _profile; // the profile chosen on a clinic staff account
  String? _profileSessionToken;
  String? get profileSessionToken => _profileSessionToken;
  AppUser?
  _user; // what the app sees: the account, or the account acting as the profile
  AppUser? get currentUser => _user;
  bool get isLoggedIn => _user != null;

  /// Returns the Firebase ID token of the currently authenticated user.
/// The Cloudflare Worker uses this token to verify the user's identity.
  Future<String> getFirebaseIdToken({bool forceRefresh = false}) async {
    final fbUser = _fa.currentUser;

    if (fbUser == null) {
      throw ApiException(401, 'Please log in again.');
    }

    try{
      final token = await fbUser.getIdToken(forceRefresh);

      if (token == null || token.isEmpty) {
        throw ApiException(401, 'Unable to verify your account.');
      }

      return token;
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }
  /// True for the shared clinic staff account (a profile is chosen after login).
  bool get isStaffAccount => _account?.role == 'clinic_staff';
  StaffProfile? get activeProfile => _profile;

  void _apply() {
    final a = _account;
    final p = _profile;
    if (a == null) {
      _user = null;
    } else if (a.role == 'clinic_staff' && p != null) {
      _user = a.copyWith(role: p.role, name: p.name, profileId: p.id);
    } else {
      _user = a;
    }
  }

  void _clear() {
    _account = null;
    _profile = null;
    _user = null;
  }

  /// Runs once when the app starts: restores the saved login, if any.
  Future<void> init() async {
    try {
      final fbUser = await _fa.authStateChanges().first;
      if (fbUser != null) await _loadProfile(fbUser.uid);
    } catch (_) {
      _clear(); // the app still opens; the user can log in again
    }
  }

  Future<void> _loadProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data();
    if (data == null) {
      await _fa.signOut();
      _clear();
      throw ApiException(404, 'This account has no profile. Please sign up.');
    }
    final u = AppUser.fromMap(uid, data);
    if (kIsWeb && u.role == 'user') {
      await _fa.signOut();
      _clear();
      throw ApiException(
        403,
        'This website is for clinic staff. Patients please use the mobile app.',
      );
    }
    if ((u.role == 'doctor' ||
            u.role == 'receptionist' ||
            u.role == 'clinic_staff') &&
        u.status != 'active') {
      await _fa.signOut();
      _clear();
      throw ApiException(
        403,
        'This account is inactive. Please contact the clinic administrator.',
      );
    }
    _account = u;
    _apply();
  }

  ApiException _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return ApiException(401, 'Incorrect email or password.');
      case 'email-already-in-use':
        return ApiException(
          409,
          'That email is already registered. Try logging in.',
        );
      case 'weak-password':
      case 'invalid-email':
        return ApiException(
          422,
          e.message ?? 'Please check the details you entered.',
        );
      case 'too-many-requests':
        return ApiException(
          429,
          'Too many attempts. Please wait a moment and try again.',
        );
      case 'user-disabled':
        return ApiException(403, 'This account has been disabled.');
      case 'network-request-failed':
        return ApiException(
          0,
          'Cannot reach the server. Check your internet connection and try again.',
        );
      default:
        return ApiException(
          500,
          'Something went wrong (${e.code}). Please try again.',
        );
    }
  }

  // Sign up. Consent is stored with the account as a record.
  // For ages 9-17 the guardian and assent fields are filled in.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required DateTime dateOfBirth,
    required String privacyVersion,
    String? guardianName,
    String? guardianRelationship,
    String? guardianContact,
    bool guardianConsent = false,
    bool minorAssent = false,
  }) async {
    UserCredential? cred;
    try {
      cred = await _fa.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      await _db.collection('users').doc(uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': 'user',
        'status': 'active',
        'clinicId': null,
        'phone': null,
        'address': null,
        'hasPhoto': false,
        'dateOfBirth': isoDate(dateOfBirth),
        'privacyNoticeVersion': privacyVersion,
        'privacyConsent': true,
        'healthDataConsent': true,
        'consentedAt': FieldValue.serverTimestamp(),
        'guardianName': guardianName,
        'guardianRelationship': guardianRelationship,
        'guardianContact': guardianContact,
        'guardianConsent': guardianConsent,
        'minorAssent': minorAssent,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _loadProfile(uid);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      try {
        await cred?.user?.delete(); // do not leave a login without a profile
      } catch (_) {}
      throw apiErrorFrom(e);
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final cred = await _fa.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile(cred.user!.uid);
      if (_user != null &&
          _user!.role != 'user' &&
          _user!.role != 'clinic_staff') {
        AuditLog.record(action: 'login');
      }
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  // Firebase emails a reset LINK (there is no code step any more).
  Future<void> resetPassword(String email) async {
    try {
      await _fa.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Do not reveal whether the email has an account.
      if (e.code == 'user-not-found') return;
      throw _authError(e);
    }
  }

  // ---- profile --------------------------------------------------------

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? address,
  }) async {
    final u = _user;
    if (u == null) throw ApiException(401, 'Please log in again.');
    try {
      await _db.collection('users').doc(u.id).update({
        'name': name,
        'phone': phone,
        'address': address,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadProfile(u.id);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// Compresses the picture (about 256 px, under 30 KB) and stores it in Firestore.
  Future<void> uploadPhoto(Uint8List bytes, String fileName) async {
    final u = _user;
    if (u == null) throw ApiException(401, 'Please log in again.');
    try {
      final small = await ImageCompressor.shrink(
        bytes,
        maxSide: 256,
        quality: 70,
        maxBytes: 30 * 1024,
      );
      await _db.collection('profilePhotos').doc(u.id).set({
        'data': Blob(small),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _db.collection('users').doc(u.id).update({
        'hasPhoto': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _loadProfile(u.id);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// Null when there is no picture (or it failed).
  Future<Uint8List?> loadMyPhoto() async {
    final u = _user;
    if (u?.hasPhoto != true) return null;
    try {
      final snap = await _db.collection('profilePhotos').doc(u!.id).get();
      final data = snap.data()?['data'];
      return data is Blob ? data.bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    await leaveProfile();
    await _fa.signOut();
    _clear();
  }

  /// 'user', 'receptionist' or 'doctor'.
  Future<String> getRole() async => _user?.role ?? 'user';

  // ---- clinic staff account and profiles ------------------------------------

  /// Checks the profile's password and opens that profile.
Future<void> chooseProfile(StaffProfile p, String password) async {
  final acc = _account;

  if (acc == null || acc.role != 'clinic_staff') {
    throw ApiException(
      403,
      'Please log in with the clinic staff account first.',
    );
  }

  if (!p.isActive || p.clinicId != acc.clinicId) {
    throw ApiException(403, 'This profile is not available.');
  }

  try {
    final firebaseToken = await getFirebaseIdToken();

    final response = await http
        .post(
          Uri.parse(
            '${BackendConfig.baseUrl}/api/profile/session',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $firebaseToken',
          },
          body: jsonEncode({
            'profileId': p.id,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 ||
        data is! Map<String, dynamic> ||
        data['success'] != true ||
        data['token'] is! String) {
      final message = data is Map<String, dynamic>
          ? data['error']?.toString() ??
              'Unable to start your profile session.'
          : 'Unable to start your profile session.';

      throw ApiException(response.statusCode, message);
    }

    _profileSessionToken = data['token'] as String;

    _profile = p;
    _apply();

    AuditLog.record(action: 'login');
  } on ApiException {
    rethrow;
  } catch (_) {
    throw ApiException(
      500,
      'Unable to connect to the secure profile service. Please try again.',
    );
  }
}

Future<bool> validateProfileSession() async {
  final token = _profileSessionToken;

  if (token == null || token.isEmpty) {
    return false;
  }

  try {
    final response = await http
        .post(
          Uri.parse(
            '${BackendConfig.baseUrl}/api/profile/session/validate',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      _profileSessionToken = null;
      return false;
    }

    final data = jsonDecode(response.body);

    if (data is Map<String, dynamic> && data['valid'] == true) {
      return true;
    }

    _profileSessionToken = null;
    return false;
  } catch (_) {
    return false;
  }
}
  /// Leaves the open profile (back to the profile screen).
  Future<void> leaveProfile() async {
  final token = _profileSessionToken;

  // Clear the local profile immediately.
  _profileSessionToken = null;
  _profile = null;
  _apply();

  if (token == null || token.isEmpty) {
    return;
  }

  try {
    await http
        .post(
          Uri.parse(
            '${BackendConfig.baseUrl}/api/profile/session/revoke',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({}),
        )
        .timeout(const Duration(seconds: 20));
  } catch (_) {
    // Local profile is already cleared.
  }
}

  /// Admin: creates the clinic's shared staff account.
  Future<void> createStaffAccount({
    required String email,
    required String password,
  }) async {
    final me = _user;
    if (me == null || me.role != 'admin' || me.clinicId == null) {
      throw ApiException(
        403,
        'Only the clinic administrator can create the staff account.',
      );
    }
    FirebaseApp app;
    try {
      app = Firebase.app('staffCreator');
    } catch (_) {
      app = await Firebase.initializeApp(
        name: 'staffCreator',
        options: Firebase.app().options,
      );
    }
    final second = FirebaseAuth.instanceFor(app: app);
    try {
      final cred = await second.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      try {
        final batch = _db.batch();
        batch.set(_db.collection('users').doc(uid), {
          'name': 'Clinic staff account',
          'email': email.trim().toLowerCase(),
          'role': 'clinic_staff',
          'status': 'active',
          'clinicId': me.clinicId,
          'phone': null,
          'address': null,
          'hasPhoto': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        AuditLog.addTo(
          batch,
          action: 'staff.account_created',
          targetType: 'user',
          targetId: uid,
          targetName: email.trim().toLowerCase(),
          details: 'clinic staff account',
        );
        await batch.commit();
      } catch (_) {
        await cred.user!.delete();
        rethrow;
      } finally {
        await second.signOut();
      }
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }
}
