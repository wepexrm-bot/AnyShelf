import 'package:flutter/material.dart';

/// The long-form reading "Atmospheres". These replace the app chrome palette
/// inside the reader so the text block can be tuned for the environment. The
/// ten presets match the web reader's THEME_PRESETS (background, text, accent).
enum AtmosphereId {
  light,
  dark,
  sepia,
  night,
  paper,
  modern,
  mint,
  rose,
  ocean,
  forest,
}

@immutable
class ReadingAtmosphere {
  final AtmosphereId id;
  final String label;
  final Color background; // the page surface
  final Color text; // body text color
  final Color accent; // interactive accents while reading
  final IconData icon;

  const ReadingAtmosphere({
    required this.id,
    required this.label,
    required this.background,
    required this.text,
    required this.accent,
    required this.icon,
  });

  static const ReadingAtmosphere light = ReadingAtmosphere(
    id: AtmosphereId.light,
    label: 'Light',
    background: Color(0xFFFCF9F8),
    text: Color(0xFF1B1C1C),
    accent: Color(0xFF154212),
    icon: Icons.light_mode,
  );

  static const ReadingAtmosphere dark = ReadingAtmosphere(
    id: AtmosphereId.dark,
    label: 'Dark',
    background: Color(0xFF1B1C1C),
    text: Color(0xFFE8E8E8),
    accent: Color(0xFFA1D494),
    icon: Icons.dark_mode,
  );

  static const ReadingAtmosphere sepia = ReadingAtmosphere(
    id: AtmosphereId.sepia,
    label: 'Sepia',
    background: Color(0xFFF4ECD8),
    text: Color(0xFF3B352B),
    accent: Color(0xFF6B5326),
    icon: Icons.local_cafe,
  );

  static const ReadingAtmosphere night = ReadingAtmosphere(
    id: AtmosphereId.night,
    label: 'Night',
    background: Color(0xFF0F172A),
    text: Color(0xFFCBD5E1),
    accent: Color(0xFF93C5FD),
    icon: Icons.nights_stay,
  );

  static const ReadingAtmosphere paper = ReadingAtmosphere(
    id: AtmosphereId.paper,
    label: 'Old Paper',
    background: Color(0xFFEFE5CE),
    text: Color(0xFF433A2A),
    accent: Color(0xFF7A6A3B),
    icon: Icons.park,
  );

  static const ReadingAtmosphere modern = ReadingAtmosphere(
    id: AtmosphereId.modern,
    label: 'Modern',
    background: Color(0xFFFAFAFA),
    text: Color(0xFF141414),
    accent: Color(0xFF154212),
    icon: Icons.auto_awesome,
  );

  static const ReadingAtmosphere mint = ReadingAtmosphere(
    id: AtmosphereId.mint,
    label: 'Mint',
    background: Color(0xFFEAF4EB),
    text: Color(0xFF1B2A1C),
    accent: Color(0xFF2F7D43),
    icon: Icons.spa,
  );

  static const ReadingAtmosphere rose = ReadingAtmosphere(
    id: AtmosphereId.rose,
    label: 'Rose',
    background: Color(0xFFFAEBED),
    text: Color(0xFF2C1B1E),
    accent: Color(0xFFB4455F),
    icon: Icons.local_florist,
  );

  static const ReadingAtmosphere ocean = ReadingAtmosphere(
    id: AtmosphereId.ocean,
    label: 'Ocean',
    background: Color(0xFFE6EFF7),
    text: Color(0xFF1B2A3A),
    accent: Color(0xFF3D6B9B),
    icon: Icons.water,
  );

  static const ReadingAtmosphere forest = ReadingAtmosphere(
    id: AtmosphereId.forest,
    label: 'Forest',
    background: Color(0xFFE4EFE3),
    text: Color(0xFF1C2A20),
    accent: Color(0xFF3A7D3A),
    icon: Icons.forest,
  );

  static const List<ReadingAtmosphere> all = [
    light,
    dark,
    sepia,
    night,
    paper,
    modern,
    mint,
    rose,
    ocean,
    forest,
  ];

  static ReadingAtmosphere fromId(AtmosphereId id) =>
      all.firstWhere((a) => a.id == id);

  /// Maps to the backend reading-theme id for cross-device sync. The ids match
  /// the backend VALID_THEMES / web THEME_PRESETS keys.
  String get apiId => id.name;
}
