import 'dart:convert';

/// A highlight, note, or bookmark for a book, as returned by
/// `GET /sync/annotations/{book_id}`.
///
/// `source` distinguishes reader-created annotations (`user_created`) from
/// native PDF annotations imported during extraction (`pdf_native`). Native
/// ones are anchored by text content (stored in `anchor` as JSON of
/// `{"text","context_before","context_after","page"}`), so they survive reflow.
class Annotation {
  final String id;
  final String kind; // "highlight" | "note" | "bookmark"
  final String? anchor; // reader: highlighted text / position; native: JSON anchor
  final String? color; // highlight color hex
  final String? noteText; // note body
  final String source; // "user_created" | "pdf_native"
  final int? page; // logical page (tiebreaker for native annotations)

  const Annotation({
    required this.id,
    required this.kind,
    this.anchor,
    this.color,
    this.noteText,
    this.source = 'user_created',
    this.page,
  });

  bool get isNote => kind == 'note';

  /// True when this highlight/note was imported from the original PDF, not
  /// created in the reader.
  bool get importedFromPdf => source == 'pdf_native';

  /// The quoted text an imported annotation is anchored to (from the anchor
  /// JSON). Empty for imported margin notes with no matched text.
  String? get anchoredText {
    if (!importedFromPdf || anchor == null) return anchor;
    try {
      final decoded = jsonDecode(anchor!);
      if (decoded is Map && decoded['text'] is String) {
        return (decoded['text'] as String).trim().isEmpty ? null : decoded['text'] as String;
      }
    } catch (_) {}
    return _rawFallback();
  }

  String? _rawFallback() {
    final a = anchor;
    return (a != null && a.trim().isNotEmpty) ? a : null;
  }

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'highlight',
        anchor: json['anchor'] as String?,
        color: json['color'] as String?,
        noteText: json['note_text'] as String?,
        source: json['source'] as String? ?? 'user_created',
        page: json['page'] as int?,
      );
}