import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'serene_tokens.dart';

/// Carries the active [SereneColorScheme] through the widget tree so custom
/// widgets can reach the full Serene palette beyond the standard
/// [ColorScheme] (e.g. the accent teal brand color).
@immutable
class SereneTheme extends ThemeExtension<SereneTheme> {
  final SereneColorScheme colors;
  const SereneTheme(this.colors);

  @override
  SereneTheme copyWith({SereneColorScheme? colors}) =>
      SereneTheme(colors ?? this.colors);

  @override
  SereneTheme lerp(SereneTheme? other, double t) {
    if (other is! SereneTheme) return this;
    return SereneTheme(SereneColorScheme(
      surface: Color.lerp(colors.surface, other.colors.surface, t)!,
      surfaceDim: Color.lerp(colors.surfaceDim, other.colors.surfaceDim, t)!,
      surfaceBright:
          Color.lerp(colors.surfaceBright, other.colors.surfaceBright, t)!,
      surfaceContainerLowest: Color.lerp(
          colors.surfaceContainerLowest, other.colors.surfaceContainerLowest, t)!,
      surfaceContainerLow:
          Color.lerp(colors.surfaceContainerLow, other.colors.surfaceContainerLow, t)!,
      surfaceContainer:
          Color.lerp(colors.surfaceContainer, other.colors.surfaceContainer, t)!,
      surfaceContainerHigh:
          Color.lerp(colors.surfaceContainerHigh, other.colors.surfaceContainerHigh, t)!,
      surfaceContainerHighest: Color.lerp(
          colors.surfaceContainerHighest, other.colors.surfaceContainerHighest, t)!,
      onSurface: Color.lerp(colors.onSurface, other.colors.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(colors.onSurfaceVariant, other.colors.onSurfaceVariant, t)!,
      inverseSurface:
          Color.lerp(colors.inverseSurface, other.colors.inverseSurface, t)!,
      inverseOnSurface:
          Color.lerp(colors.inverseOnSurface, other.colors.inverseOnSurface, t)!,
      outline: Color.lerp(colors.outline, other.colors.outline, t)!,
      outlineVariant:
          Color.lerp(colors.outlineVariant, other.colors.outlineVariant, t)!,
      surfaceTint: Color.lerp(colors.surfaceTint, other.colors.surfaceTint, t)!,
      primary: Color.lerp(colors.primary, other.colors.primary, t)!,
      onPrimary: Color.lerp(colors.onPrimary, other.colors.onPrimary, t)!,
      primaryContainer:
          Color.lerp(colors.primaryContainer, other.colors.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(
          colors.onPrimaryContainer, other.colors.onPrimaryContainer, t)!,
      inversePrimary:
          Color.lerp(colors.inversePrimary, other.colors.inversePrimary, t)!,
      error: Color.lerp(colors.error, other.colors.error, t)!,
      onError: Color.lerp(colors.onError, other.colors.onError, t)!,
      errorContainer:
          Color.lerp(colors.errorContainer, other.colors.errorContainer, t)!,
      onErrorContainer:
          Color.lerp(colors.onErrorContainer, other.colors.onErrorContainer, t)!,
      background: Color.lerp(colors.background, other.colors.background, t)!,
      onBackground: Color.lerp(colors.onBackground, other.colors.onBackground, t)!,
      surfaceVariant:
          Color.lerp(colors.surfaceVariant, other.colors.surfaceVariant, t)!,
      accentTeal: Color.lerp(colors.accentTeal, other.colors.accentTeal, t)!,
    ));
  }
}

/// Builds the Serene ThemeData for a given palette ("Day" or "Night").
ThemeData sereneTheme(SereneColorScheme c) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.primary,
    brightness: c == SereneColorScheme.night
        ? Brightness.dark
        : Brightness.light,
  ).copyWith(
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryContainer,
    onPrimaryContainer: c.onPrimaryContainer,
    secondary: c.primary,
    onSecondary: c.onPrimary,
    secondaryContainer: c.primaryContainer,
    onSecondaryContainer: c.onPrimaryContainer,
    error: c.error,
    onError: c.onError,
    errorContainer: c.errorContainer,
    onErrorContainer: c.onErrorContainer,
    surface: c.surface,
    onSurface: c.onSurface,
    onSurfaceVariant: c.onSurfaceVariant,
    surfaceContainerLowest: c.surfaceContainerLowest,
    surfaceContainerLow: c.surfaceContainerLow,
    surfaceContainer: c.surfaceContainer,
    surfaceContainerHigh: c.surfaceContainerHigh,
    surfaceContainerHighest: c.surfaceContainerHighest,
    outline: c.outline,
    outlineVariant: c.outlineVariant,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
    fontFamily: SereneType.uiFamily,
    scaffoldBackgroundColor: c.background,
    extensions: [SereneTheme(c)],
  );

  final textTheme = base.textTheme.copyWith(
    displayLarge: GoogleFonts.playfairDisplay(
        textStyle: SereneType.displayLg.copyWith(color: c.onBackground)),
    headlineLarge: GoogleFonts.playfairDisplay(
        textStyle: SereneType.headlineLg.copyWith(color: c.onBackground)),
    headlineMedium: GoogleFonts.playfairDisplay(
        textStyle: SereneType.headlineMobile.copyWith(color: c.onBackground)),
    titleLarge: GoogleFonts.playfairDisplay(
        textStyle: SereneType.title.copyWith(color: c.onSurface)),
    bodyLarge: GoogleFonts.sourceSerif4(
        textStyle: SereneType.readingBody.copyWith(color: c.onBackground)),
    bodyMedium: GoogleFonts.inter(
        textStyle: SereneType.uiBody.copyWith(color: c.onBackground)),
    labelLarge: GoogleFonts.inter(
        textStyle: SereneType.labelMd.copyWith(color: c.onSurface)),
    labelMedium: GoogleFonts.inter(
        textStyle: SereneType.labelSm.copyWith(color: c.onSurfaceVariant)),
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.onBackground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: SereneType.headlineMobile.copyWith(color: c.onBackground),
      toolbarHeight: 64,
    ),
    cardTheme: CardThemeData(
      color: c.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: SereneShape.card),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: c.surfaceVariant, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceContainerLow,
      hintStyle: SereneType.uiBody.copyWith(color: c.outline),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(SereneShape.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(SereneShape.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: c.primary, width: 2),
        borderRadius: BorderRadius.only(
          bottomLeft: SereneShape.md,
          bottomRight: SereneShape.md,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: SereneShape.fullPill),
        textStyle: SereneType.labelMd.copyWith(
          color: c.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        side: BorderSide(color: c.outlineVariant),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: SereneShape.fullPill),
        textStyle: SereneType.labelMd.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        textStyle: SereneType.labelMd,
        shape: RoundedRectangleBorder(borderRadius: SereneShape.fullPill),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? c.onPrimary : c.outline),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? c.primary : c.surfaceVariant),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 8,
      activeTrackColor: c.primary,
      inactiveTrackColor: c.outlineVariant,
      thumbColor: c.primary,
      overlayColor: c.primary.withValues(alpha: 0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: SereneShape.sheetTop),
      clipBehavior: Clip.antiAlias,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inverseSurface,
      contentTextStyle:
          SereneType.uiBody.copyWith(color: c.inverseOnSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.md)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.lg)),
    ),
  );
}
