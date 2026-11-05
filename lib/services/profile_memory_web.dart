import 'package:web/web.dart' as web;

/// Website: keeps the open profile id in sessionStorage (this tab only).
class ProfileMemory {
  static const _key = 'bcksnap_open_profile';

  static String? read() {
    try {
      return web.window.sessionStorage.getItem(_key);
    } catch (_) {
      return null;
    }
  }

  static void save(String profileId) {
    try {
      web.window.sessionStorage.setItem(_key, profileId);
    } catch (_) {}
  }

  static void clear() {
    try {
      web.window.sessionStorage.removeItem(_key);
    } catch (_) {}
  }
}
