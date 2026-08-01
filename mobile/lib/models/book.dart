class Book {
  final String id;
  final String title;
  final String extractionStatus;
  final double? reflowConfidence;
  final bool isScanned;

  Book({
    required this.id,
    required this.title,
    required this.extractionStatus,
    this.reflowConfidence,
    this.isScanned = false,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'],
      title: json['title'],
      extractionStatus: json['extraction_status'],
      reflowConfidence: (json['reflow_confidence'] as num?)?.toDouble(),
      isScanned: json['is_scanned'] ?? false,
    );
  }

  /// True once the extraction pipeline has produced a confident-enough
  /// structured text version to support full font/theme reflow.
  bool get reflowAvailable => (reflowConfidence ?? 0) >= 0.5;
}
