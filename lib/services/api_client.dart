import 'package:firebase_core/firebase_core.dart' show FirebaseException;

/// Thrown whenever a service fails. [message] is safe to show to the user.
class ApiException implements Exception {
  final int statusCode; // 0 = could not reach the server
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Turns a Firebase error into a friendly [ApiException].
ApiException apiErrorFrom(FirebaseException e) {
  switch (e.code) {
    case 'unavailable':
    case 'network-request-failed':
      return ApiException(
        0,
        'Cannot reach the server. Check your internet connection and try again.',
      );
    case 'permission-denied':
      return ApiException(403, 'You do not have permission to do that.');
    case 'not-found':
      return ApiException(404, 'That item no longer exists.');
    default:
      return ApiException(
        500,
        'Something went wrong (${e.code}). Please try again.',
      );
  }
}
