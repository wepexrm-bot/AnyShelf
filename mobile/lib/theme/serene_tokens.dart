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
    surface: Color(0xFFFCF9F8),
    surfaceDim: Color(0xFFDCD9D9),
    surfaceBright: Color(0xFFFCF9F8),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F3F2),
    surfaceContainer: Color(0xFFF0EDED),
    surfaceContainerHigh: Color(0xFFEAE7E7),
    surfaceContainerHighest: Color(0xFFE4E2E1),
    onSurface: Color(0xFF1B1C1C),
    onSurfaceVariant: Color(0xFF42493E),
    inverseSurface: Color(0xFF303030),
    inverseOnSurface: Color(0xFFF3F0EF),
    outline: Color(0xFF72796E),
    outlineVariant: Color(0xFFC2C9BB),
    surfaceTint: Color(0xFF3B6934),
    primary: Color(0xFF154212),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF2D5A27),
    onPrimaryContainer: Color(0xFF9DD090),
    inversePrimary: Color(0xFFA1D494),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    background: Color(0xFFFCF9F8),
    onBackground: Color(0xFF1B1C1C),
    surfaceVariant: Color(0xFFE4E2E1),
    accentTeal: Color(0xFF154212),
  );

  static const SereneColorScheme night = SereneColorScheme(
    surface: Color(0xFF121412),
    surfaceDim: Color(0xFF121412),
    surfaceBright: Color(0xFF383A37),
    surfaceContainerLowest: Color(0xFF0D0F0D),
    surfaceContainerLow: Color(0xFF1A1C1A),
    surfaceContainer: Color(0xFF1E201E),
    surfaceContainerHigh: Color(0xFF292A28),
    surfaceContainerHighest: Color(0xFF333533),
    onSurface: Color(0xFFE2E3DF),
    onSurfaceVariant: Color(0xFFC2C9BB),
    inverseSurface: Color(0xFFE2E3DF),
    inverseOnSurface: Color(0xFF2F312E),
    outline: Color(0xFF8C9387),
    outlineVariant: Color(0xFF42493E),
    surfaceTint: Color(0xFFA1D494),
    primary: Color(0xFFA1D494),
    onPrimary: Color(0xFF0A3909),
    primaryContainer: Color(0xFF2D5A27),
    onPrimaryContainer: Color(0xFF9DD090),
    inversePrimary: Color(0xFF3B6934),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    background: Color(0xFF121412),
    onBackground: Color(0xFFE2E3DF),
    surfaceVariant: Color(0xFF333533),
    accentTeal: Color(0xFFA1D494),
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

/// Typography: Playfair Display for display/headings, Inter for app chrome,
/// Source Serif 4 for long-form reading — matching the web design system.
/// Reading body uses a generous 1.7x line height.
abstract final class SereneType {
  static const String displayFamily = 'Playfair Display';
  static const String uiFamily = 'Inter';
  static const String bodyFamily = 'Source Serif 4';

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
    fontFamily: bodyFamily,
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
