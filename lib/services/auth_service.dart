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
import 'profile_memory.dart';
import '../core/profile_crypto.dart';
import '../models/staff_profile.dart';

/// What happened after a Google or Facebook sign-in.
enum SocialResult { signedIn, needsProfile, cancelled }

class AuthService {
  // One shared instance, so every screen sees the same logged-in user.
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final FirebaseAuth _fa = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AppUser? _account; // the Firebase account's own record
  StaffProfile? _profile; // the profile chosen on a clinic staff account
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
    if (acc == null || acc.role != 'clinic_staff') return;
    final id = ProfileMemory.read();
    if (id == null) return;
    try {
      final snap = await _db.collection('staffProfiles').doc(id).get();
      final data = snap.data();
      if (data == null) {
        ProfileMemory.clear();
        return;
      }
      final p = StaffProfile.fromMap(snap.id, data);
      if (!p.isActive || p.clinicId != acc.clinicId) {
        ProfileMemory.clear();
        return;
      }
      _profile = p;
      _apply();
    } catch (_) {
      // Could not check: the picker simply shows again.
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

  Future<SocialResult> signInWithFacebook() =>
      _signInWith(FacebookAuthProvider()..addScope('email'));

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
    if (ProfileCrypto.hash(p.salt, password) != p.hash) {
      throw ApiException(401, 'Incorrect password.');
    }
    _profile = p;
    _apply();
    ProfileMemory.save(p.id);
    AuditLog.record(action: 'login');
  }

  /// Leaves the open profile (back to the profile screen).
  void leaveProfile() {
    _profile = null;
    _apply();
    ProfileMemory.clear();
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
