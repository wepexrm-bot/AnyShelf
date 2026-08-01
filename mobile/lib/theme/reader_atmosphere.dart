import 'package:flutter/material.dart';

/// The long-form reading "Atmospheres". These replace the app chrome palette
/// inside the reader so the text block can be tuned for the environment:
/// bright daylight, warm low-blue-light, neutral gray, and pitch dark.
enum AtmosphereId { day, sepia, gray, night }

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

  static const ReadingAtmosphere day = ReadingAtmosphere(
    id: AtmosphereId.day,
    label: 'Light',
    background: Color(0xFFFDFCFB),
    text: Color(0xFF1A1A1A),
    accent: Color(0xFF134E4A),
    icon: Icons.light_mode,
  );

  static const ReadingAtmosphere sepia = ReadingAtmosphere(
    id: AtmosphereId.sepia,
    label: 'Sepia',
    background: Color(0xFFF4EBD0),
    text: Color(0xFF433422),
    accent: Color(0xFF6B5326),
    icon: Icons.local_cafe,
  );

  static const ReadingAtmosphere gray = ReadingAtmosphere(
    id: AtmosphereId.gray,
    label: 'Gray',
    background: Color(0xFFE8E6E4),
    text: Color(0xFF1A1C1C),
    accent: Color(0xFF316763),
    icon: Icons.contrast,
  );

  static const ReadingAtmosphere night = ReadingAtmosphere(
    id: AtmosphereId.night,
    label: 'Night',
    background: Color(0xFF121212),
    text: Color(0xFFD1D1D1),
    accent: Color(0xFF9AD1CB),
    icon: Icons.dark_mode,
  );

  static const List<ReadingAtmosphere> all = [day, sepia, gray, night];

  static ReadingAtmosphere fromId(AtmosphereId id) =>
      all.firstWhere((a) => a.id == id);

  /// Maps to the backend reading-theme id for cross-device sync.
  String get apiId => switch (id) {
        AtmosphereId.day => 'light',
        AtmosphereId.sepia => 'sepia',
        AtmosphereId.gray => 'dark',
        AtmosphereId.night => 'night',
      };
}
