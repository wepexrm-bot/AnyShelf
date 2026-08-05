/// A bookshelf as returned by the backend `GET /shelves/` and `GET /shelves/{id}`.
class Shelf {
  final String id;
  final String name;
  final String? description;
  final bool isPublic;
  final String? color;
  final String? bannerUrl;
  final int bookCount;
  final DateTime? createdAt;
  final List<String> bookIds;
  final List<ShelfBook> books;

  const Shelf({
    required this.id,
    required this.name,
    this.description,
    this.isPublic = false,
    this.color,
    this.bannerUrl,
    this.bookCount = 0,
    this.createdAt,
    this.bookIds = const [],
    this.books = const [],
  });

  factory Shelf.fromJson(Map<String, dynamic> json) {
    final books = ((json['books'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ShelfBook.fromJson)
        .toList();
    return Shelf(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Untitled',
      description: json['description'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      color: json['color'] as String?,
      bannerUrl: json['banner_url'] as String?,
      bookCount: (json['book_count'] as num?)?.toInt() ?? books.length,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      bookIds: ((json['book_ids'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      books: books,
    );
  }

  /// Serialises a shelf for the offline library cache. The per-book [books]
  /// detail list is dropped -- it's only used by the shelf detail screen,
  /// which refetches it -- and [bookIds] + [bookCount] carry membership.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'name': name,
        'description': description,
        'is_public': isPublic,
        'color': color,
        'book_count': bookCount,
        'book_ids': bookIds,
        'created_at': createdAt?.toIso8601String(),
      };

  /// Rebuilds a cached shelf (mirror of [toCacheJson]).
  factory Shelf.fromCacheJson(Map<String, dynamic> json) => Shelf(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? 'Untitled',
        description: json['description'] as String?,
        isPublic: json['is_public'] as bool? ?? false,
        color: json['color'] as String?,
        bookCount: (json['book_count'] as num?)?.toInt() ?? 0,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
        bookIds: ((json['book_ids'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// A lightweight book entry inside a shelf detail.
class ShelfBook {
  final String id;
  final String title;
  final String? extractionStatus;

  const ShelfBook({required this.id, required this.title, this.extractionStatus});

  factory ShelfBook.fromJson(Map<String, dynamic> json) => ShelfBook(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'Untitled',
        extractionStatus: json['extraction_status'] as String?,
      );
}
