// Remembers, for this browser tab only, which staff profile is open, so a
// page refresh does not send the clinic staff account back to the picker.
// Only the profile id is kept (never a password), and it is cleared when the
// tab closes, when the profile is left, and when the account logs out.
export 'profile_memory_stub.dart'
    if (dart.library.js_interop) 'profile_memory_web.dart';
