/// A highlight or sticky note created in the reader, as returned by
/// `GET /sync/annotations/{book_id}`.
class Annotation {
  final String id;
  final String kind; // "highlight" | "note"
  final String? anchor; // highlighted text (for highlights)
  final String? color; // highlight color hex
  final String? noteText; // note body

  const Annotation({
    required this.id,
    required this.kind,
    this.anchor,
    this.color,
    this.noteText,
  });

  bool get isNote => kind == 'note';

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
        id: json['id'] as String,
        kind: json['kind'] as String? ?? 'highlight',
        anchor: json['anchor'] as String?,
        color: json['color'] as String?,
        noteText: json['note_text'] as String?,
      );
}
