import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../core/format.dart';
import '../core/image_compress.dart';
import '../models/app_user.dart';
import 'api_client.dart';
import 'audit_log.dart';
import 'profile_memory.dart';
import '../models/staff_profile.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

/// What happened after a Google or Facebook sign-in.
enum SocialResult { signedIn, needsProfile, cancelled }

class AuthService {
  // One shared instance, so every screen sees the same logged-in user.
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final FirebaseAuth _fa = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _profileSessionKey = 'bcksnap_profile_session';

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

    try {
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
    _profileSessionToken = null;
    ProfileMemory.clear();
  }

  /// Runs once when the app starts: restores the saved login, if any.
  Future<void> init() async {
    try {
      final fbUser = await _fa.authStateChanges().first;
      if (fbUser != null) {
        await _loadProfile(fbUser.uid);
        await _restoreProfile();
      }
    } catch (_) {
      _clear(); // the app still opens; the user can log in again
    }
  }

  /// After a page refresh: reopen the profile this browser tab had open, so
  /// the clinic staff account does not go back to the profile picker.
  Future<void> _restoreProfile() async {
    final acc = _account;

    // Only shared clinic staff accounts need profile restoration.
    if (acc == null || acc.role != 'clinic_staff') return;

    String? token;

    try {
      token = await _secureStorage.read(key: _profileSessionKey);
    } catch (_) {
      // Storage could not be accessed. Do not delete anything.
      return;
    }

    if (token == null || token.isEmpty) return;

    try {
      // Ask the Cloudflare Worker to validate the saved session.
      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/profile/session/validate'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 20));

      // The Worker explicitly rejected or expired this session.
      if (response.statusCode == 401 || response.statusCode == 403) {
        await _secureStorage.delete(key: _profileSessionKey);
        ProfileMemory.clear();
        _profileSessionToken = null;
        _profile = null;
        _apply();
        return;
      }

      // Other server errors may be temporary. Preserve the token.
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic> || data['valid'] != true) {
        return;
      }

      final profileData = data['profile'];

      if (profileData is! Map<String, dynamic>) return;

      final profileId = profileData['id']?.toString();
      final clinicId = profileData['clinicId']?.toString();
      final role = profileData['role']?.toString();

      if (profileId == null ||
          profileId.isEmpty ||
          clinicId != acc.clinicId ||
          (role != 'doctor' && role != 'receptionist' && role != 'pt')) {
        await _secureStorage.delete(key: _profileSessionKey);
        ProfileMemory.clear();
        return;
      }

      // Retrieve the actual staff profile from Firestore.
      final snap = await _db.collection('staffProfiles').doc(profileId).get();

      final profileMap = snap.data();

      if (profileMap == null) {
        await _secureStorage.delete(key: _profileSessionKey);
        ProfileMemory.clear();
        return;
      }

      final p = StaffProfile.fromMap(snap.id, profileMap);

      // Double-check that the profile still belongs to this clinic
      // and has the expected role and active status.
      if (!p.isActive ||
          p.clinicId != acc.clinicId ||
          p.clinicId != clinicId ||
          p.role != role) {
        await _secureStorage.delete(key: _profileSessionKey);
        ProfileMemory.clear();
        return;
      }

      // Restore the authenticated staff profile.
      _profileSessionToken = token;
      _profile = p;
      _apply();
    } catch (_) {
      // Network or temporary service failure:
      // Keep the saved token so restoration can be retried.
      return;
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
    if (!kIsWeb && u.role == 'developer') {
      await _fa.signOut();
      _clear();
      throw ApiException(403, 'The developer portal is on the website.');
    }
    if (u.role == 'admin' && u.status != 'active') {
      await _fa.signOut();
      _clear();
      throw ApiException(
        403,
        u.status == 'rejected'
            ? 'Your clinic registration was not approved. Please contact the developer.'
            : 'Your clinic registration is still waiting for approval.',
      );
    }
    // Doctors, receptionists and clinic staff must use the website.
    // Administrators may use either platform.
    const staffRoles = ['doctor', 'receptionist', 'pt', 'clinic_staff'];

    if (!kIsWeb && staffRoles.contains(u.role)) {
      await _fa.signOut();
      _clear();
      throw ApiException(403, 'Staff accounts must use the clinic web portal.');
    }

    // Inactive staff accounts cannot log in.
    if ((u.role == 'doctor' ||
            u.role == 'receptionist' ||
            u.role == 'clinic_staff' ||
            u.role == 'pt') &&
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
      case 'account-exists-with-different-credential':
        return ApiException(
          409,
          'An account with this email already exists. '
          'Log in with your email and password instead.',
        );
      case 'operation-not-allowed':
        return ApiException(
          403,
          'This sign-in method is not turned on yet. Ask the administrator.',
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
      // Send the confirmation email. If it fails, the patient can tap
      // "Resend" on the verification screen.
      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {}
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
  // ---- email verification ---------------------------------------------------

  /// True when the signed-in Firebase account has confirmed its email.
  bool get isEmailVerified => _fa.currentUser?.emailVerified ?? false;

  /// Sends the confirmation link again.
  Future<void> sendVerificationEmail() async {
    final u = _fa.currentUser;
    if (u == null) throw ApiException(401, 'Please log in again.');
    try {
      await u.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  /// Asks Firebase again whether the link was opened. True = verified.
  Future<bool> refreshEmailVerified() async {
    final u = _fa.currentUser;
    if (u == null) return false;
    try {
      await u.reload();
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
    return _fa.currentUser?.emailVerified ?? false;
  }

  // ---- Google and Facebook --------------------------------------------------

  /// A social sign-in whose profile (date of birth, consent) is not saved yet.
  User? _pendingSocial;
  bool get hasPendingSocial => _pendingSocial != null;
  String? get pendingSocialName => _pendingSocial?.displayName;
  String? get pendingSocialEmail => _pendingSocial?.email;

  Future<SocialResult> signInWithGoogle() => _signInWith(
    GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
  );

  Future<SocialResult> signInWithFacebook() async {
    try {
      // Keep the existing Firebase provider flow for web.
      if (kIsWeb) {
        return await _signInWith(FacebookAuthProvider()..addScope('email'));
      }

      // Open native Facebook Login on Android.
      final result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.cancelled) {
        return SocialResult.cancelled;
      }

      if (result.status != LoginStatus.success || result.accessToken == null) {
        throw ApiException(
          500,
          result.message ?? 'Facebook sign-in failed. Please try again.',
        );
      }

      // Exchange the Facebook token for Firebase credentials.
      final credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );

      final cred = await _fa.signInWithCredential(credential);
      final user = cred.user;

      if (user == null) {
        throw ApiException(500, 'Sign-in failed. Please try again.');
      }

      if ((user.email ?? '').isEmpty) {
        await _fa.signOut();
        throw ApiException(
          422,
          'That account has no email address. Please use another sign-in method.',
        );
      }

      final snap = await _db.collection('users').doc(user.uid).get();

      if (!snap.exists) {
        _pendingSocial = user;
        return SocialResult.needsProfile;
      }

      _pendingSocial = null;
      await _loadProfile(user.uid);

      return SocialResult.signedIn;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'popup-closed-by-user') {
        return SocialResult.cancelled;
      }
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  Future<SocialResult> _signInWith(AuthProvider provider) async {
    try {
      final cred = await _fa.signInWithProvider(provider);
      final user = cred.user;
      if (user == null) {
        throw ApiException(500, 'Sign-in failed. Please try again.');
      }
      if ((user.email ?? '').isEmpty) {
        await _fa.signOut();
        throw ApiException(
          422,
          'That account has no email address. Please use another sign-in method.',
        );
      }
      final snap = await _db.collection('users').doc(user.uid).get();
      if (!snap.exists) {
        // First time: still needs date of birth and consent.
        _pendingSocial = user;
        return SocialResult.needsProfile;
      }
      _pendingSocial = null;
      await _loadProfile(user.uid);
      return SocialResult.signedIn;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' ||
          e.code == 'web-context-canceled' ||
          e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return SocialResult.cancelled;
      }
      throw _authError(e);
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// Saves the profile of a first-time Google/Facebook user.
  Future<void> completeSocialSignUp({
    required String name,
    required DateTime dateOfBirth,
    required String privacyVersion,
    String? guardianName,
    String? guardianRelationship,
    String? guardianContact,
    bool guardianConsent = false,
    bool minorAssent = false,
  }) async {
    final u = _pendingSocial ?? _fa.currentUser;
    if (u == null) throw ApiException(401, 'Please sign in again.');
    try {
      await _db.collection('users').doc(u.uid).set({
        'name': name.trim(),
        'email': (u.email ?? '').toLowerCase(),
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
      _pendingSocial = null;
      await _loadProfile(u.uid);
      if (!u.emailVerified) {
        try {
          await u.sendEmailVerification();
        } catch (_) {}
      }
    } on FirebaseException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  /// The person left the "complete your profile" step.
  Future<void> cancelSocialSignUp() async {
    _pendingSocial = null;
    await _fa.signOut();
    _clear();
  }

  // ---- profile --------------------------------------------------------
  // ---- clinic registration (website) ---------------------------------------

  /// A clinic asks to join. It creates the administrator login (pending) and
  /// the registration request. The developer approves it later.
  Future<void> registerClinic({
    required String applicantName,
    required String email,
    required String password,
    required String clinicName,
    required String address,
    required String phone,
    required String clinicEmail,
    required List<String> services,
    required bool supportsPhysical,
    required bool supportsOnline,
    String? description,
    String? licenseNumber,
  }) async {
    UserCredential? cred;
    try {
      cred = await _fa.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user!.uid;
      final batch = _db.batch();
      batch.set(_db.collection('users').doc(uid), {
        'name': applicantName.trim(),
        'email': email.trim().toLowerCase(),
        'role': 'admin',
        'status': 'pending',
        'clinicId': null,
        'phone': null,
        'address': null,
        'hasPhoto': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(_db.collection('clinicRegistrations').doc(uid), {
        'applicantId': uid,
        'applicantName': applicantName.trim(),
        'applicantEmail': email.trim().toLowerCase(),
        'clinicName': clinicName.trim(),
        'address': address.trim(),
        'phone': phone,
        'clinicEmail': clinicEmail.trim(),
        'description': (description ?? '').trim().isEmpty
            ? null
            : description!.trim(),
        'licenseNumber': (licenseNumber ?? '').trim().isEmpty
            ? null
            : licenseNumber!.trim(),
        'services': services,
        'supportsPhysical': supportsPhysical,
        'supportsOnline': supportsOnline,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {}
      await _fa.signOut();
      _clear();
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on FirebaseException catch (e) {
      try {
        await cred?.user?.delete(); // do not leave a login without a request
      } catch (_) {}
      throw apiErrorFrom(e);
    }
  }

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
            Uri.parse('${BackendConfig.baseUrl}/api/profile/session'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $firebaseToken',
            },
            body: jsonEncode({'profileId': p.id, 'password': password}),
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
      final token = data['token'] as String;

      // Save the session securely so it survives browser refreshes.
      await _secureStorage.write(key: _profileSessionKey, value: token);

      _profileSessionToken = data['token'] as String;

      _profile = p;
      _apply();
      ProfileMemory.save(p.id);
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
            Uri.parse('${BackendConfig.baseUrl}/api/profile/session/validate'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 20));

      // The server explicitly rejected the session.
      if (response.statusCode == 401 || response.statusCode == 403) {
        _profileSessionToken = null;
        _profile = null;
        ProfileMemory.clear();
        _apply();

        await _secureStorage.delete(key: _profileSessionKey);
        return false;
      }

      // Preserve the token for temporary server errors.
      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic> && data['valid'] == true) {
        return true;
      }

      // A successful response explicitly says the session is invalid.
      _profileSessionToken = null;
      _profile = null;
      ProfileMemory.clear();
      _apply();

      await _secureStorage.delete(key: _profileSessionKey);
      return false;
    } catch (_) {
      // Network or temporary service failure.
      // Keep the saved token so validation can be retried.
      return false;
    }
  }

  Future<void> leaveProfile() async {
    final token = _profileSessionToken;

    // Clear the local session immediately.
    _profileSessionToken = null;
    _profile = null;
    ProfileMemory.clear();
    _apply();

    // Remove the saved token from secure storage.
    try {
      await _secureStorage.delete(key: _profileSessionKey);
    } catch (_) {
      // Continue with server-side revocation.
    }

    if (token == null || token.isEmpty) return;

    // Revoke the session on the Cloudflare Worker.
    try {
      await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/api/profile/session/revoke'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Local session is already cleared.
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
