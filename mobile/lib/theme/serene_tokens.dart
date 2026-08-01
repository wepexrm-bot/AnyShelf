import 'package:flutter/material.dart';

/// Serene Library design tokens from the AnyShelf design system.
///
/// Two named palettes ("Day" and "Night") drive the whole app chrome, while
/// long-form reading surfaces use the dedicated "atmosphere" presets in
/// [reader_atmosphere.dart].
@immutable
class SereneColorScheme {
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color inverseSurface;
  final Color inverseOnSurface;
  final Color outline;
  final Color outlineVariant;
  final Color surfaceTint;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color inversePrimary;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color background;
  final Color onBackground;
  final Color surfaceVariant;
  final Color accentTeal;

  const SereneColorScheme({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.outline,
    required this.outlineVariant,
    required this.surfaceTint,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.inversePrimary,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.background,
    required this.onBackground,
    required this.surfaceVariant,
    required this.accentTeal,
  });

  static const SereneColorScheme day = SereneColorScheme(
    surface: Color(0xFFFAF9F8),
    surfaceDim: Color(0xFFDADAD9),
    surfaceBright: Color(0xFFFAF9F8),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF4F3F2),
    surfaceContainer: Color(0xFFEEEEED),
    surfaceContainerHigh: Color(0xFFE9E8E7),
    surfaceContainerHighest: Color(0xFFE3E2E1),
    onSurface: Color(0xFF1A1C1C),
    onSurfaceVariant: Color(0xFF404847),
    inverseSurface: Color(0xFF2F3130),
    inverseOnSurface: Color(0xFFF1F0F0),
    outline: Color(0xFF707977),
    outlineVariant: Color(0xFFBFC8C6),
    surfaceTint: Color(0xFF316763),
    primary: Color(0xFF003633),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF134E4A),
    onPrimaryContainer: Color(0xFF87BEB8),
    inversePrimary: Color(0xFF9AD1CB),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    background: Color(0xFFFAF9F8),
    onBackground: Color(0xFF1A1C1C),
    surfaceVariant: Color(0xFFE3E2E1),
    accentTeal: Color(0xFF134E4A),
  );

  static const SereneColorScheme night = SereneColorScheme(
    surface: Color(0xFF131313),
    surfaceDim: Color(0xFF131313),
    surfaceBright: Color(0xFF393939),
    surfaceContainerLowest: Color(0xFF0E0E0E),
    surfaceContainerLow: Color(0xFF1C1B1B),
    surfaceContainer: Color(0xFF201F1F),
    surfaceContainerHigh: Color(0xFF2A2A2A),
    surfaceContainerHighest: Color(0xFF353534),
    onSurface: Color(0xFFE5E2E1),
    onSurfaceVariant: Color(0xFFC3C6D0),
    inverseSurface: Color(0xFFE5E2E1),
    inverseOnSurface: Color(0xFF313030),
    outline: Color(0xFF8D9199),
    outlineVariant: Color(0xFF43474F),
    surfaceTint: Color(0xFFA9C8FB),
    primary: Color(0xFFD3E2FF),
    onPrimary: Color(0xFF0A315B),
    primaryContainer: Color(0xFFA8C7FA),
    onPrimaryContainer: Color(0xFF33537F),
    inversePrimary: Color(0xFF405F8C),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    background: Color(0xFF131313),
    onBackground: Color(0xFFE5E2E1),
    surfaceVariant: Color(0xFF353534),
    accentTeal: Color(0xFF9AD1CB),
  );

  SereneColorScheme copyWith({Color? accentTeal}) => SereneColorScheme(
        surface: surface,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
        surfaceContainerLowest: surfaceContainerLowest,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainerHighest: surfaceContainerHighest,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        inverseSurface: inverseSurface,
        inverseOnSurface: inverseOnSurface,
        outline: outline,
        outlineVariant: outlineVariant,
        surfaceTint: surfaceTint,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        inversePrimary: inversePrimary,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        background: background,
        onBackground: onBackground,
        surfaceVariant: surfaceVariant,
        accentTeal: accentTeal ?? this.accentTeal,
      );
}

/// The Serene design system is animated by an 8px grid with "soft and
/// approachable" corners. Book covers use a subtle 4px radius; surfaces and
/// controls 8-16px; interactive pills are fully rounded.
abstract final class SereneShape {
  static const Radius sm = Radius.circular(4);
  static const Radius md = Radius.circular(8);
  static const Radius lg = Radius.circular(16);
  static const Radius xl = Radius.circular(24);
  static const Radius full = Radius.circular(9999);

  static const BorderRadius card = BorderRadius.all(lg);
  static const BorderRadius sheetTop = BorderRadius.vertical(top: xl);
  static const BorderRadius fullPill = BorderRadius.all(full);
}

/// Fluid & Focused spacing: 8px unit, 24px gutter, 16px mobile safe margins,
/// 48px tablet margins.
abstract final class SereneSpacing {
  static const double unit = 8;
  static const double gutter = 24;
  static const double marginMobile = 16;
  static const double marginTablet = 48;
}

/// Typography: Literata for content/headings ("consuming"), Hanken Grotesk
/// for app chrome ("managing"). Reading body uses a generous 1.7x line height.
abstract final class SereneType {
  static const String displayFamily = 'Literata';
  static const String uiFamily = 'HankenGrotesk';

  static const TextStyle displayLg = TextStyle(
    fontFamily: displayFamily,
    fontSize: 48,
    height: 56 / 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: displayFamily,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle headlineMobile = TextStyle(
    fontFamily: displayFamily,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle title = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle readingBody = TextStyle(
    fontFamily: displayFamily,
    fontSize: 18,
    height: 32 / 18,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle uiBody = TextStyle(
    fontFamily: uiFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: uiFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.01,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: uiFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
  );
}

/// Breakpoints: phones get a bottom nav, tablets/larger get a side rail.
abstract final class SereneLayout {
  static const double tabletBreakpoint = 700;
}
