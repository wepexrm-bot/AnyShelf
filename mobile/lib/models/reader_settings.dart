import 'package:flutter/painting.dart';

import '../theme/reader_atmosphere.dart';

/// The reader's tunable preferences, matching the "Appearance" panel and the
/// backend `/settings/` contract.
enum ReaderMode { scroll, singlePage }

/// The fifteen type families offered in the reader, matching the web reader's
/// font options and the backend VALID_FONTS ids. [googleFamily] is the
/// runtime-loadable Google Fonts family name.
enum ReaderFont {
  serif('serif', 'Serif', 'Source Serif 4'),
  sans('sans', 'Sans', 'Inter'),
  lora('lora', 'Lora', 'Lora'),
  merriweather('merriweather', 'Merriweather', 'Merriweather'),
  garamond('garamond', 'Garamond', 'EB Garamond'),
  roboto('roboto', 'Roboto', 'Roboto'),
  opensans('opensans', 'Open Sans', 'Open Sans'),
  atkinson('atkinson', 'Atkinson', 'Atkinson Hyperlegible'),
  playfair('playfair', 'Playfair', 'Playfair Display'),
  lato('lato', 'Lato', 'Lato'),
  poppins('poppins', 'Poppins', 'Poppins'),
  nunito('nunito', 'Nunito', 'Nunito'),
  ptserif('ptserif', 'PT Serif', 'PT Serif'),
  crimson('crimson', 'Crimson', 'Crimson Pro');

  final String apiId;
  final String label;
  final String googleFamily;
  const ReaderFont(this.apiId, this.label, this.googleFamily);

  static ReaderFont fromApi(String? id) => values.firstWhere(
        (f) => f.apiId == id,
        orElse: () => ReaderFont.serif,
      );
}

/// Three line-height steps offered in the Appearance panel.
enum LineHeightLevel {
  snug('Cozy', 1.4),
  cozy('Normal', 1.7),
  airy('Airy', 2.0);

  final String label;
  final double value;
  const LineHeightLevel(this.label, this.value);
}

/// Three margin widths. Kept for API sync only — the reader is edge-to-edge.
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
  double fontSize; // 14..32
  LineHeightLevel lineHeight;
  MarginLevel margins;
  ReaderMode mode;
  bool textMode; // substitute fonts on themed paper; false => show real PDF page
  TextAlign textAlign;

  ReaderSettings({
    required this.atmosphere,
    required this.font,
    required this.fontSize,
    required this.lineHeight,
    required this.margins,
    required this.mode,
    this.textMode = true,
    this.textAlign = TextAlign.justify,
  });

  factory ReaderSettings.defaults() =>       ReaderSettings(
        atmosphere: ReadingAtmosphere.sepia,
        font: ReaderFont.serif,
        fontSize: 20,
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
    bool? textMode,
    TextAlign? textAlign,
  }) =>
      ReaderSettings(
        atmosphere: atmosphere ?? this.atmosphere,
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        margins: margins ?? this.margins,
        mode: mode ?? this.mode,
        textMode: textMode ?? this.textMode,
        textAlign: textAlign ?? this.textAlign,
      );

  /// Actual pixel value of the reading font based on the chosen family.
  String get fontFamily => font.googleFamily;

  /// The Appearance "Page Zoom" control: fontSize is repurposed as a zoom
  /// factor (default 20 = 100%), mirroring the web reader. Scales the whole
  /// positioned page up/down instead of reflowing text.
  double get pageZoom => (fontSize / 20).clamp(0.6, 1.6);

  /// Maps the local settings onto the backend `/settings/` payload so reading
  /// preferences sync across devices.
  Map<String, dynamic> toApi() => {
        'theme': atmosphere.apiId,
        'font_family': font.apiId,
        'font_size': fontSize.round(),
        'line_spacing': lineHeight.value,
        'margins': switch (margins) {
          MarginLevel.small => 'small',
          MarginLevel.medium => 'medium',
          MarginLevel.large => 'large',
        },
        'reading_mode': mode == ReaderMode.scroll ? 'scroll' : 'paginate',
        'page_layout': 'single',
      };

  factory ReaderSettings.fromApi(Map<String, dynamic> json) => ReaderSettings(
        atmosphere: ReadingAtmosphere.fromId(
          AtmosphereId.values.firstWhere(
            (a) => a.name == json['theme'],
            orElse: () => AtmosphereId.sepia,
          ),
        ),
        font: ReaderFont.fromApi(json['font_family'] as String?),
        fontSize: ((json['font_size'] as num?)?.toDouble() ?? 18)
            .clamp(14, 32),
        lineHeight: switch ((json['line_spacing'] as num?)?.toDouble()) {
          final v when v != null && v <= 1.5 => LineHeightLevel.snug,
          final v when v != null && v >= 1.9 => LineHeightLevel.airy,
          _ => LineHeightLevel.cozy,
        },
        margins: switch (json['margins']) {
          'small' => MarginLevel.small,
          'large' => MarginLevel.large,
          _ => MarginLevel.medium,
        },
        mode: json['reading_mode'] == 'paginate'
            ? ReaderMode.singlePage
            : ReaderMode.scroll,
      );
}