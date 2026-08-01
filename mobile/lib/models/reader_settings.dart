import '../theme/reader_atmosphere.dart';

/// The reader's tunable preferences, matching the "Appearance" panel and the
/// backend `/settings/` contract.
enum ReaderFont { literata, grotesk, system }

enum ReaderMode { scroll, paginated }

/// Three line-height steps offered in the Appearance panel.
enum LineHeightLevel {
  snug('Cozy', 1.4),
  cozy('Normal', 1.7),
  airy('Airy', 2.0);

  final String label;
  final double value;
  const LineHeightLevel(this.label, this.value);
}

/// Three margin widths.
enum MarginLevel {
  small('Narrow', 32),
  medium('Normal', 64),
  large('Wide', 96);

  final String label;
  final double px;
  const MarginLevel(this.label, this.px);
}

class ReaderSettings {
  ReadingAtmosphere atmosphere;
  ReaderFont font;
  double fontSize; // 12..32
  LineHeightLevel lineHeight;
  MarginLevel margins;
  ReaderMode mode;

  ReaderSettings({
    required this.atmosphere,
    required this.font,
    required this.fontSize,
    required this.lineHeight,
    required this.margins,
    required this.mode,
  });

  factory ReaderSettings.defaults() => ReaderSettings(
        atmosphere: ReadingAtmosphere.sepia,
        font: ReaderFont.literata,
        fontSize: 18,
        lineHeight: LineHeightLevel.cozy,
        margins: MarginLevel.medium,
        mode: ReaderMode.scroll,
      );

  ReaderSettings copyWith({
    ReadingAtmosphere? atmosphere,
    ReaderFont? font,
    double? fontSize,
    LineHeightLevel? lineHeight,
    MarginLevel? margins,
    ReaderMode? mode,
  }) =>
      ReaderSettings(
        atmosphere: atmosphere ?? this.atmosphere,
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        margins: margins ?? this.margins,
        mode: mode ?? this.mode,
      );

  /// Actual pixel value of the reading font based on the chosen family.
  String get fontFamily => switch (font) {
        ReaderFont.literata => 'Literata',
        ReaderFont.grotesk => 'HankenGrotesk',
        ReaderFont.system => 'Roboto',
      };

  /// Maps the local settings onto the backend `/settings/` payload so reading
  /// preferences sync across devices.
  Map<String, dynamic> toApi() => {
        'theme': atmosphere.apiId,
        'font_family': switch (font) {
          ReaderFont.literata => 'serif',
          ReaderFont.grotesk => 'sans',
          ReaderFont.system => 'roboto',
        },
        'font_size': fontSize.round(),
        'line_spacing': lineHeight.value,
        'margins': switch (margins) {
          MarginLevel.small => 'small',
          MarginLevel.medium => 'medium',
          MarginLevel.large => 'large',
        },
        'reading_mode': mode == ReaderMode.scroll ? 'scroll' : 'paginate',
      };

  factory ReaderSettings.fromApi(Map<String, dynamic> json) => ReaderSettings(
        atmosphere: switch (json['theme']) {
          'sepia' => ReadingAtmosphere.sepia,
          'night' => ReadingAtmosphere.night,
          'dark' => ReadingAtmosphere.gray,
          _ => ReadingAtmosphere.day,
        },
        font: switch (json['font_family']) {
          'sans' => ReaderFont.grotesk,
          'roboto' => ReaderFont.system,
          _ => ReaderFont.literata,
        },
        fontSize: ((json['font_size'] as num?)?.toDouble() ?? 18)
            .clamp(12, 32),
        lineHeight: switch ((json['line_spacing'] as num?)?.toDouble()) {
          <= 1.5 => LineHeightLevel.snug,
          >= 1.9 => LineHeightLevel.airy,
          _ => LineHeightLevel.cozy,
        },
        margins: switch (json['margins']) {
          'small' => MarginLevel.small,
          'large' => MarginLevel.large,
          _ => MarginLevel.medium,
        },
        mode: json['reading_mode'] == 'paginate'
            ? ReaderMode.paginated
            : ReaderMode.scroll,
      );
}
