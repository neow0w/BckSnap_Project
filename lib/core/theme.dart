import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The BckSnap colours. Change a value here and the whole app follows.
/// These are matched by eye from your mockups. If any looks slightly off,
/// copy the exact hex code from Figma.
class AppColors {
  static const Color primary = Color(0xFF0096D6);
  static const Color fieldFill = Color(0xFFE8F2F9);
  static const Color tonal = Color(0xFFDCEBF5);
  static const Color border = Color(0xFFD5E6F2);
  static const Color text = Color(0xFF1B2733);
  static const Color hint = Color(0xFF8A97A3);

  // Dark mode
  static const Color primaryLight = Color(0xFF4CB5E6); // readable on dark
  static const Color darkBackground = Color(0xFF0F161D);
  static const Color darkSurface = Color(0xFF182530);
  static const Color darkFieldFill = Color(0xFF223140);
  static const Color darkTonal = Color(0xFF263646);
  static const Color darkBorder = Color(0xFF2B3B4A);
  static const Color darkText = Color(0xFFE6EDF3);

  // Result levels
  static const Color normal = Color(0xFF1F9D6B);
  static const Color mild = Color(0xFFD99A1E);
  static const Color high = Color(0xFFD93A3A);

  // Sign-in buttons
  static const Color google = Color(0xFFEA4335);
  static const Color facebook = Color(0xFF1877F2);
}

final ThemeData appTheme = _build(Brightness.light);
final ThemeData appDarkTheme = _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  const radius = 12.0;
  final dark = brightness == Brightness.dark;

  final bg = dark ? AppColors.darkBackground : Colors.white;
  final surface = dark ? AppColors.darkSurface : Colors.white;
  final textColor = dark ? AppColors.darkText : AppColors.text;
  final accent = dark ? AppColors.primaryLight : AppColors.primary;
  final fieldFill = dark ? AppColors.darkFieldFill : AppColors.fieldFill;
  final border = dark ? AppColors.darkBorder : AppColors.border;

  OutlineInputBorder inputBorder([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );

  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
      ).copyWith(
        primary: accent,
        surface: surface,
        error: AppColors.high,
        surfaceContainerHighest: dark ? AppColors.darkTonal : null,
      );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = base.textTheme.apply(
    fontFamily: GoogleFonts.poppins().fontFamily,
    bodyColor: textColor,
    displayColor: textColor,
  );

  final buttonText = GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: accent),
      actionsIconTheme: IconThemeData(color: accent),
      titleTextStyle: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: accent,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.poppins(color: AppColors.hint, fontSize: 14),
      labelStyle: GoogleFonts.poppins(color: AppColors.hint, fontSize: 14),
      border: inputBorder(),
      enabledBorder: inputBorder(),
      disabledBorder: inputBorder(),
      focusedBorder: inputBorder(accent, 1.5),
      errorBorder: inputBorder(AppColors.high, 1),
      focusedErrorBorder: inputBorder(AppColors.high, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent),
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: border),
  );
}
