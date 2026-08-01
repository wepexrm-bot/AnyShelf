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
      );
}

/// A reflowable text block, mirroring the structured-JSON shape produced by
/// the extraction pipeline: `{ pages: [{ page_number, blocks: [{ kind, text,
/// level }] }] }`.
class TextBlock {
  final String kind; // "heading" | "paragraph"
  final String text;
  final int level;

  const TextBlock({required this.kind, required this.text, this.level = 0});

  bool get isHeading => kind == 'heading';

  factory TextBlock.fromJson(Map<String, dynamic> json) => TextBlock(
        kind: json['kind'] as String? ?? 'paragraph',
        text: json['text'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
      );
}

class StructuredPage {
  final int pageNumber;
  final List<TextBlock> blocks;

  const StructuredPage({required this.pageNumber, required this.blocks});

  factory StructuredPage.fromJson(Map<String, dynamic> json) => StructuredPage(
        pageNumber: (json['page_number'] as num?)?.toInt() ?? 0,
        blocks: ((json['blocks'] as List?) ?? const [])
            .map((b) => TextBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class StructuredText {
  final List<StructuredPage> pages;

  const StructuredText({required this.pages});

  /// Flat list of every block across all pages — convenient for scroll mode.
  List<TextBlock> get allBlocks =>
      [for (final p in pages) ...p.blocks];

  factory StructuredText.fromJson(Map<String, dynamic> json) => StructuredText(
        pages: ((json['pages'] as List?) ?? const [])
            .map((p) => StructuredPage.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
