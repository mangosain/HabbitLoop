import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppPalette {
  static const green = Color(0xFF45AD66);
  static const deepGreen = Color(0xFF247D44);
  static const mint = Color(0xFFEAF7EC);
  static const lavender = Color(0xFFF0EAFE);
  static const purple = Color(0xFF9373D6);
  static const peach = Color(0xFFFFEFE5);
  static const amber = Color(0xFFFFC971);
  static const yellow = Color(0xFFFFF4D9);
  static const red = Color(0xFFF0757C);
  static const ink = Color(0xFF1E2833);
  static const muted = Color(0xFF81909A);
  static const cream = Color(0xFFFCFCF9);
  static const border = Color(0xFFE8EDE9);
}

SystemUiOverlayStyle appStatusBarStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: brightness,
      statusBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );

ThemeData appTheme({bool dark = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.green,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    scaffoldBackgroundColor: dark ? const Color(0xFF101717) : AppPalette.cream,
    colorScheme: scheme.copyWith(primary: AppPalette.green),
    textTheme:
        GoogleFonts.nunitoSansTextTheme(
          ThemeData(brightness: scheme.brightness).textTheme,
        ).apply(
          bodyColor: dark ? Colors.white : AppPalette.ink,
          displayColor: dark ? Colors.white : AppPalette.ink,
        ),
    appBarTheme: AppBarTheme(
      systemOverlayStyle: appStatusBarStyle(scheme.brightness),
      backgroundColor: Colors.transparent,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      filled: true,
      fillColor: dark ? const Color(0xFF222D2C) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: dark ? Colors.white24 : AppPalette.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: AppPalette.green, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF202B2A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
