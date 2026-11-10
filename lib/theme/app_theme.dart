import 'package:flutter/material.dart';

/// One palette for the whole app: navy + blue + cyan, with gold reserved for
/// trophies and champions only. Every text colour below was chosen to stay
/// readable on the card colour it is used with (contrast >= 4.5:1).
class AppColors {
  static const primary = Color(0xFF0B8A63);
  static const primaryDark = Color(0xFF065F46);
  static const cyan = Color(0xFFFBBF24);
  static const cyanDeep = Color(0xFFB45309);
  static const accent = cyan; // secondary accent (was gold; gold clashed with the blues)
  static const gold = Color(0xFFE8B84A); // trophies / champion only
  static const glowBlue = Color(0xFF34D399);
  static const success = Color(0xFF12B886);
  static const danger = Color(0xFFFF6B6B);
  static const warning = Color(0xFFF59E0B);

  static const darkBg = Color(0xFF04130F);
  static const darkSurface = Color(0xFF08201A);
  static const darkCard = Color(0xFF0C2B23);
  static const darkText = Color(0xFFEFFAF5);
  static const darkTextMuted = Color(0xFFA9CFC0);

  static const lightBg = Color(0xFFC4E9D6);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF0B2A20);
  static const lightTextMuted = Color(0xFF3E6657);
}

/// Muted (secondary) text colour that matches the current page: soft blue-grey in
/// dark mode, deep slate blue in light mode.
Color mutedText(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

class AppTheme {
  static TextTheme _text(Color body, Color muted) => TextTheme(
        displayLarge: TextStyle(color: body),
        headlineMedium: TextStyle(color: body, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: body, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: body, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: body, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: body),
        bodyMedium: TextStyle(color: body),
        bodySmall: TextStyle(color: muted),
        labelLarge: TextStyle(color: body, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: muted),
        labelSmall: TextStyle(color: muted),
      );

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.cyanDeep,
    onSecondary: Colors.white,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightText,
    onSurfaceVariant: AppColors.lightTextMuted,
  );

  static final ColorScheme _darkScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF34D399),
    onPrimary: const Color(0xFF04211A),
    secondary: AppColors.cyan,
    onSecondary: const Color(0xFF2B1D00),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkText,
    onSurfaceVariant: AppColors.darkTextMuted,
  );

  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.transparent, // the blue artwork shows through
    primaryColor: AppColors.primary,
    colorScheme: _lightScheme,
    fontFamily: 'Roboto',
    textTheme: _text(AppColors.lightText, AppColors.lightTextMuted),
    iconTheme: const IconThemeData(color: AppColors.lightText),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: AppColors.primaryDark,
      centerTitle: true,
      titleTextStyle: TextStyle(
          color: AppColors.primaryDark, fontSize: 19, fontWeight: FontWeight.w800),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.primaryDark,
      unselectedLabelColor: Color(0xFF4F8A74),
      indicatorColor: AppColors.cyanDeep,
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 0,
      shadowColor: AppColors.primary.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      labelStyle: const TextStyle(color: AppColors.lightTextMuted),
      hintStyle: const TextStyle(color: AppColors.lightTextMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(color: AppColors.lightText, fontWeight: FontWeight.w600),
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      backgroundColor: Colors.white.withValues(alpha: 0.9),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.lightText,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    useMaterial3: true,
  );

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    primaryColor: AppColors.primary,
    colorScheme: _darkScheme,
    fontFamily: 'Roboto',
    textTheme: _text(AppColors.darkText, AppColors.darkTextMuted),
    iconTheme: const IconThemeData(color: AppColors.darkText),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Color(0xFF6EE7B7),
      centerTitle: true,
      titleTextStyle: TextStyle(
          color: Color(0xFF6EE7B7), fontSize: 19, fontWeight: FontWeight.w800),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Color(0xFF6EE7B7),
      unselectedLabelColor: Color(0xFF9FD5BF),
      indicatorColor: Color(0xFF6EE7B7),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard.withValues(alpha: 0.92),
      elevation: 0,
      shadowColor: AppColors.glowBlue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.glowBlue.withValues(alpha: 0.28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.glowBlue.withValues(alpha: 0.3)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkCard.withValues(alpha: 0.85),
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      hintStyle: const TextStyle(color: AppColors.darkTextMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.cyan,
        side: const BorderSide(color: AppColors.cyan),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w600),
      selectedColor: AppColors.primary.withValues(alpha: 0.45),
      backgroundColor: AppColors.darkCard,
      side: BorderSide(color: AppColors.glowBlue.withValues(alpha: 0.3)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF123C30),
      contentTextStyle: TextStyle(color: AppColors.darkText),
      behavior: SnackBarBehavior.floating,
    ),
    useMaterial3: true,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [AppColors.primary, AppColors.primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Knockout badges and accents: cyan to deep blue, in harmony with the
  /// league gradient (replaces the former gold gradient).
  static const LinearGradient knockoutGradient = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Kept for the champion / trophy highlights only.
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD86B), Color(0xFFFFA53E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
