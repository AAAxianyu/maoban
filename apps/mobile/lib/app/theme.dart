import 'package:flutter/material.dart';

// Light palette. Widgets read colors through [AppColors] so dark mode works.
const cream = Color(0xFFF6EBD8);
const surface = Color(0xFFFFF9ED);
const ink = Color(0xFF392A25);
const secondaryInk = Color(0xFF6B584D);
const coral = Color(0xFFD56B57);
const coralInk = Color(0xFF963E30);
const buttonInk = Color(0xFF241711);
const sage = Color(0xFF56744B);
const line = Color(0xFFDFCCB3);
// Aliases: inside AppColors these names would resolve to its own fields.
const _line = line, _ink = ink, _secondaryInk = secondaryInk;

/// Project tokens that Material's ColorScheme has no slot for.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color paper, line, ink, secondaryInk, success, onSuccess;
  final Color offlineBanner, errorBanner, onBanner;
  const AppColors({
    required this.paper,
    required this.line,
    required this.ink,
    required this.secondaryInk,
    required this.success,
    required this.onSuccess,
    required this.offlineBanner,
    required this.errorBanner,
    required this.onBanner,
  });

  static const light = AppColors(
    paper: surface,
    line: _line,
    ink: _ink,
    secondaryInk: _secondaryInk,
    success: sage,
    onSuccess: Colors.white,
    offlineBanner: Color(0xFFEDE3D1),
    errorBanner: Color(0xFFF2D9C2),
    onBanner: _ink,
  );

  static const dark = AppColors(
    paper: Color(0xFF2E2420),
    line: Color(0xFF4A3B33),
    ink: Color(0xFFF3E6D3),
    secondaryInk: Color(0xFFCBB7A5),
    success: Color(0xFF8DB07F),
    onSuccess: Color(0xFF14200F),
    offlineBanner: Color(0xFF3A302A),
    errorBanner: Color(0xFF5A2F26),
    onBanner: Color(0xFFF3E6D3),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      paper: mix(paper, other.paper),
      line: mix(line, other.line),
      ink: mix(ink, other.ink),
      secondaryInk: mix(secondaryInk, other.secondaryInk),
      success: mix(success, other.success),
      onSuccess: mix(onSuccess, other.onSuccess),
      offlineBanner: mix(offlineBanner, other.offlineBanner),
      errorBanner: mix(errorBanner, other.errorBanner),
      onBanner: mix(onBanner, other.onBanner),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}

TextTheme _text(AppColors c) => TextTheme(
  headlineMedium: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: c.ink,
  ),
  titleLarge: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: c.ink,
  ),
  titleMedium: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: c.ink,
  ),
  titleSmall: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: c.ink,
  ),
  bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: c.ink),
  bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: c.secondaryInk),
  // DESIGN.md: supporting copy never below 13.
  bodySmall: TextStyle(fontSize: 13, height: 1.4, color: c.secondaryInk),
  labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  labelMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  labelSmall: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? AppColors.dark : AppColors.light;
  final background = dark ? const Color(0xFF221A17) : cream;
  final scheme = dark
      ? ColorScheme.dark(
          primary: const Color(0xFFE88C77),
          onPrimary: buttonInk,
          secondary: c.success,
          onSecondary: c.onSuccess,
          secondaryContainer: const Color(0xFF3B4A33),
          onSecondaryContainer: c.ink,
          surface: c.paper,
          onSurface: c.ink,
          error: const Color(0xFFFFB4A8),
        )
      : ColorScheme.light(
          primary: coral,
          onPrimary: buttonInk,
          secondary: sage,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFDAE3CB),
          onSecondaryContainer: ink,
          surface: surface,
          onSurface: ink,
          error: const Color(0xFF9D3026),
        );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: scheme,
    extensions: [c],
    textTheme: _text(c),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: c.ink,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.paper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: buttonInk,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: c.ink,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? const Color(0xFFF0A08D) : coralInk,
        minimumSize: const Size(48, 48),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.paper,
      indicatorColor: dark ? const Color(0xFF5A3B32) : const Color(0xFFF2C4AE),
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: c.ink, size: 24)),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 24),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

ThemeData appTheme() => _theme(Brightness.light);
ThemeData appDarkTheme() => _theme(Brightness.dark);
