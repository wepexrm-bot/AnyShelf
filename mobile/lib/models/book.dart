/// A book as returned by the backend `GET /books/` and `GET /books/{id}`.
class Book {
  final String id;
  final String title;
  final String? author;
  final String? genre;
  final String? coverUrl;
  final String? pdfUrl;
  final String? structuredTextUrl;
  final String? extractionStatus;
  final double? reflowConfidence;
  final bool isScanned;
  final double? progress; // current reading position (fraction 0..1)
  final DateTime? createdAt;

  const Book({
    required this.id,
    required this.title,
    this.author,
    this.genre,
    this.coverUrl,
    this.pdfUrl,
    this.structuredTextUrl,
    this.extractionStatus,
    this.reflowConfidence,
    this.isScanned = false,
    this.progress,
    this.createdAt,
  });

  /// Reflow mode is offered when the extraction pipeline judged the text
  /// clean enough to rebuild (confidence >= 0.5) — otherwise the book falls
  /// back to fixed-layout + theme-only rendering.
  bool get reflowAvailable =>
      reflowConfidence != null && reflowConfidence! >= 0.5;

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Untitled',
        author: json['author'] as String?,
        genre: json['genre'] as String?,
        coverUrl: json['cover_url'] as String?,
        pdfUrl: json['pdf_url'] as String?,
        structuredTextUrl: json['structured_text_url'] as String?,
        extractionStatus: json['extraction_status'] as String?,
        reflowConfidence: (json['reflow_confidence'] as num?)?.toDouble(),
        isScanned: json['is_scanned'] as bool? ?? false,
        progress: (json['progress'] as num?)?.toDouble(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  /// Serialises a book for the offline library cache. Deliberately excludes
  /// presigned URLs (pdf_url / structured_text_url) -- they expire and are
  /// only meaningful for the session that fetched them.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'author': author,
        'genre': genre,
        'cover_url': coverUrl,
        'extraction_status': extractionStatus,
        'reflow_confidence': reflowConfidence,
        'is_scanned': isScanned,
        'progress': progress,
        'created_at': createdAt?.toIso8601String(),
      };

  /// Rebuilds a cached book (mirror of [toCacheJson]).
  factory Book.fromCacheJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Untitled',
        author: json['author'] as String?,
        genre: json['genre'] as String?,
        coverUrl: json['cover_url'] as String?,
        extractionStatus: json['extraction_status'] as String?,
        reflowConfidence: (json['reflow_confidence'] as num?)?.toDouble(),
        isScanned: json['is_scanned'] as bool? ?? false,
        progress: (json['progress'] as num?)?.toDouble(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  Book copyWith({double? progress}) => Book(
        id: id,
        title: title,
        author: author,
        genre: genre,
        coverUrl: coverUrl,
        pdfUrl: pdfUrl,
        structuredTextUrl: structuredTextUrl,
        extractionStatus: extractionStatus,
        reflowConfidence: reflowConfidence,
        isScanned: isScanned,
        progress: progress ?? this.progress,
        createdAt: createdAt,
      );
}

/// A positioned text run on a page, mirroring the backend `textlayer-v1`
/// schema's page runs: `{t, x, y, fs, w, f, flags}`. Coordinates are in PDF
/// points; `x`/`y` are the left edge and the baseline.
class TextRun {
  final String t; // run text
  final double x; // left edge (points)
  final double y; // baseline (points)
  final double fs; // font size (points)
  final double w; // advance width (points) -- scaleX target
  final int flags; // 16 = bold, 2 = italic
  final int start; // char offset of this run within the page run stream
  final int end;

  const TextRun({
    required this.t,
    required this.x,
    required this.y,
    required this.fs,
    required this.w,
    required this.flags,
    required this.start,
    required this.end,
  });

  bool get isBold => (flags & 16) != 0;
  bool get isItalic => (flags & 2) != 0;

  factory TextRun.fromJson(Map<String, dynamic> json, int start) {
    final t = json['t'] as String? ?? '';
    return TextRun(
      t: t,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      fs: (json['fs'] as num?)?.toDouble() ?? 0,
      w: (json['w'] as num?)?.toDouble() ?? 0,
      flags: (json['flags'] as num?)?.toInt() ?? 0,
      start: start,
      end: start + t.length,
    );
  }
}

/// One PDF page's text layer: dimensions in points plus the positioned runs.
class TextLayerPage {
  final int page; // 0-based physical page
  final double width;
  final double height;
  final double rotation;
  final bool hasImage; // page renders at least one image (cover/illustration)
  final List<TextRun> runs;

  const TextLayerPage({
    required this.page,
    required this.width,
    required this.height,
    required this.rotation,
    required this.hasImage,
    required this.runs,
  });

  /// The full page text as a single string (concatenated run stream, which is
  /// exactly how the backend computes char offsets).
  String get text => runs.map((r) => r.t).join('');

  factory TextLayerPage.fromJson(Map<String, dynamic> json) {
    var acc = 0;
    final runs = ((json['runs'] as List?) ?? const [])
        .map((r) {
          final run = TextRun.fromJson(r as Map<String, dynamic>, acc);
          acc += run.t.length;
          return run;
        })
        .toList();
    return TextLayerPage(
      page: (json['page'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 612,
      height: (json['height'] as num?)?.toDouble() ?? 792,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      hasImage: json['has_image'] as bool? ?? false,
      runs: runs,
    );
  }
}

/// A table-of-contents entry (from the PDF outline), `page` is 0-based.
class OutlineEntry {
  final int level;
  final String title;
  final int page;

  const OutlineEntry({required this.level, required this.title, required this.page});

  factory OutlineEntry.fromJson(Map<String, dynamic> json) => OutlineEntry(
        level: (json['level'] as num?)?.toInt() ?? 1,
        title: json['title'] as String? ?? '',
        page: (json['page'] as num?)?.toInt() ?? 0,
      );
}

/// The positioned text layer for a whole book: `textlayer-v1` schema JSON
/// served from `structured_text_url`.
class TextLayer {
  final String schema;
  final List<OutlineEntry> outline;
  final double? textConfidence;
  final double? reflowConfidence;
  final bool isScanned;
  final List<TextLayerPage> pages;

  TextLayer({
    required this.schema,
    required this.outline,
    required this.textConfidence,
    required this.reflowConfidence,
    required this.isScanned,
    required this.pages,
  });

  /// Total character count across every page (the denominator for progress).
  int get totalChars => _cumulativeChars[pages.length];

  /// Cumulative char counts: `cumulativeChars[i]` = chars before page `i`.
  late final List<int> _cumulativeChars = _computeCumulativeChars();

  List<int> _computeCumulativeChars() {
    final acc = <int>[0];
    var total = 0;
    for (final p in pages) {
      total += p.text.length;
      acc.add(total);
    }
    return acc;
  }

  /// Number of characters before page [pageIndex].
  int charsBefore(int pageIndex) =>
      pageIndex <= 0 ? 0 : _cumulativeChars[pageIndex.clamp(0, pages.length)];

  /// Reading fraction (0..1) at the start of page [pageIndex].
  double fractionAt(int pageIndex) {
    final total = totalChars;
    if (total <= 0) return pageIndex <= 0 ? 0.0 : 1.0;
    return (charsBefore(pageIndex) / total).clamp(0.0, 1.0);
  }

  /// Reading fraction (0..1) at the *end* of page [pageIndex].
  double fractionThrough(int pageIndex) {
    final total = totalChars;
    if (total <= 0) return 1.0;
    final idx = pageIndex.clamp(0, pages.length - 1);
    return (_cumulativeChars[idx + 1] / total).clamp(0.0, 1.0);
  }

  /// The page whose char range contains reading fraction [fraction] (0..1),
  /// else the last page. Clamped to the physical page count.
  int pageForFraction(double fraction) {
    if (pages.isEmpty) return 0;
    final target = (fraction.clamp(0.0, 1.0) * totalChars);
    for (var i = 0; i < pages.length; i++) {
      if (target <= _cumulativeChars[i + 1]) return i;
    }
    return pages.length - 1;
  }

  /// Whether this payload is a positioned text layer the reader can render.
  bool get hasRuns => schema == 'textlayer-v1' && pages.any((p) => p.runs.isNotEmpty);

  factory TextLayer.fromJson(Map<String, dynamic> json) => TextLayer(
        schema: json['schema'] as String? ?? '',
        outline: ((json['outline'] as List?) ?? const [])
            .map((o) => OutlineEntry.fromJson(o as Map<String, dynamic>))
            .toList(),
        textConfidence: (json['text_confidence'] as num?)?.toDouble(),
        reflowConfidence: (json['reflow_confidence'] as num?)?.toDouble(),
        isScanned: json['is_scanned'] as bool? ?? false,
        pages: ((json['pages'] as List?) ?? const [])
            .map((p) => TextLayerPage.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

