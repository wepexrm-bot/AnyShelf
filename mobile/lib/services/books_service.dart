import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/annotation.dart';
import '../models/book.dart';
import 'api_client.dart';
import 'book_content_cache.dart';
import 'pdf_renderer.dart';

class BooksService {
  final ApiClient api;
  BooksService({ApiClient? api}) : api = api ?? ApiClient();

  /// Genre choices for the upload form, matching the web's list.
  static const List<String> genres = [
    'Fiction', 'Literary Fiction', 'Classics', 'Contemporary', 'Romance',
    'Fantasy', 'Science Fiction', 'Dystopian', 'Mystery', 'Crime', 'Thriller',
    'Suspense', 'Horror', 'Gothic', 'Historical Fiction', 'Adventure',
    'Western', 'Young Adult', 'New Adult', "Children's", 'Middle Grade',
    'Picture Book', 'Graphic Novel', 'Comics', 'Manga', 'Poetry', 'Drama',
    'Short Stories', 'Essays', 'Anthology', 'Biography', 'Autobiography',
    'Memoir', 'Travel', 'Food & Cooking', 'Self-Help', 'Personal Development',
    'Psychology', 'Philosophy', 'Religion', 'Spirituality', 'Mythology',
    'Fairy Tales', 'Folklore', 'Satire', 'Humor', 'Science', 'History',
    'Politics', 'Economics', 'Business', 'Technology', 'Nature', 'True Crime',
    'Sports', 'Music', 'Art', 'Health & Fitness', 'Education', 'Reference',
    'Non-Fiction', 'Other',
  ];

  /// Uploads a PDF file with metadata and an optional cover image. The PDF is
  /// streamed from [fileStream] so large files never need to be fully buffered
  /// in memory. Returns the uploaded book payload.
  Future<Map<String, dynamic>> upload({
    required String filename,
    required Stream<List<int>> fileStream,
    required int fileLength,
    required String title,
    required String author,
    String? genre,
    Uint8List? coverBytes,
    String? coverName,
  }) async {
    final files = <http.MultipartFile>[
      http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: filename,
        contentType: MediaType('application', 'pdf'),
      ),
      if (coverBytes != null && coverBytes.isNotEmpty)
        http.MultipartFile.fromBytes(
          'cover',
          coverBytes,
          filename: coverName ?? 'cover.jpg',
          contentType: _coverContentType(coverName),
        ),
    ];
    final data = await api.postMultipart('/books/upload', fields: {
      'title': title,
      'author': author,
      if (genre != null && genre.isNotEmpty) 'genre': genre,
    }, files: files);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static MediaType _coverContentType(String? name) {
    final lower = (name ?? '').toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  Future<List<Book>> list() async {
    final data = await api.get('/books/');
    final items = data as List;
    return items
        .map((b) => _reachable(Book.fromJson(b as Map<String, dynamic>)))
        .toList();
  }

  Future<Book> get(String id) async {
    final data = await api.get('/books/$id');
    return _reachable(Book.fromJson(data as Map<String, dynamic>));
  }

  /// Edits a book's metadata (title / author / genre).
  Future<void> update(String id,
      {String? title, String? author, String? genre}) async {
    await api.put('/books/$id', body: {
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (genre != null) 'genre': genre,
    });
  }

  /// Replaces a book's cover image and returns the new cover URL.
  Future<String> updateCover(String id,
      {required Uint8List coverBytes, required String coverName}) async {
    final data = await api.postMultipart(
      '/books/$id/cover',
      method: 'PUT',
      fields: const {},
      files: [
        http.MultipartFile.fromBytes(
          'file',
          coverBytes,
          filename: coverName,
          contentType: _coverContentType(coverName),
        ),
      ],
    );
    final url = data is Map ? data['cover_url'] as String? : null;
    return url ?? '';
  }

  Book _reachable(Book b) => Book(
        id: b.id,
        title: b.title,
        author: b.author,
        genre: b.genre,
        coverUrl: api.reachableUrl(b.coverUrl),
        pdfUrl: api.reachableUrl(b.pdfUrl),
        structuredTextUrl: api.reachableUrl(b.structuredTextUrl),
        extractionStatus: b.extractionStatus,
        reflowConfidence: b.reflowConfidence,
        isScanned: b.isScanned,
        progress: b.progress,
        createdAt: b.createdAt,
      );

  /// Live text-extraction progress for a book that is still processing.
  /// Returns `(status, progress)` where status is one of
  /// `pending` / `processing` / `done` / `failed` and progress is 0-100.
  Future<({String status, double progress})> extractionStatus(String bookId) async {
    final data = await api.get('/books/$bookId/progress') as Map<String, dynamic>;
    return (
      status: (data['extraction_status'] as String?) ?? '',
      progress: (data['progress'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Asks the backend to re-run the extraction pipeline for a book, regenerating
  /// its text layer (and new fields such as per-page `has_image`).
  Future<void> reExtract(String bookId) async {
    await api.post('/books/$bookId/re-extract', body: const {});
  }

  /// Reading position for a book (fraction 0..1 across the whole document).
  Future<double> progress(String bookId) async {
    final data = await api.get('/sync/progress/$bookId') as Map;
    return _normaliseProgress(data);
  }

  /// Reading progress for every owned book in one request (fraction 0..1),
  /// so a library refresh is O(1) calls instead of one per book.
  Future<Map<String, double>> allProgress() async {
    final data = await api.get('/books/progress') as List;
    return {
      for (final item in data.whereType<Map>())
        item['book_id'] as String: _normaliseProgress(item),
    };
  }

  static double _normaliseProgress(Map item) {
    final page = (item['current_page'] as num?)?.toDouble() ?? 0;
    final offset = (item['current_offset'] as num?)?.toDouble() ?? 0;
    // current_offset carries the overall fraction (mobile writer). The web
    // writes a 0-100 percentage into current_page, so normalise that to a
    // fraction too -- otherwise a book read on web resumes at the wrong place
    // on mobile.
    if (offset > 0) return offset;
    if (page > 0) return (page / 100).clamp(0.0, 1.0);
    return 0;
  }

  Future<void> saveProgress(String bookId,
      {double? fraction, double? page}) async {
    final f = (fraction ?? 0).clamp(0.0, 1.0);
    await api.post('/sync/progress', body: {
      'book_id': bookId,
      // current_page stores the 0-100 percentage the web and backend stats
      // read; current_offset stores the 0-1 fraction the mobile reader uses.
      'current_page': page ?? (f * 100),
      'current_offset': f,
    });
  }

  Future<TextLayer?> textLayer(Book book) async {
    final url = book.structuredTextUrl;
    if (url == null) return null;
    final cache = BookContentCache.instance;
    final sourceTag = BookContentCache.sourceTagFrom(url);
    // Same-session reopen: serve the decoded layer straight from memory, so
    // reopening a book skips the multi-MB disk read + JSON decode entirely.
    final inMemory = cache.cachedLayer(book.id);
    if (inMemory != null) return inMemory;
    List<int>? body;
    // Otherwise read the layer from disk when the cached copy is fresh and
    // still matches the current structured-text URL (skips re-downloading the
    // multi-MB JSON on every open).
    if (await cache.isValidLayer(book.id, sourceTag: sourceTag)) {
      body = await cache.layer(book.id);
    }
    if (body == null) {
      try {
        final res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 90)); // pre-signed URL, no auth
        if (res.statusCode != 200 || res.body.isEmpty) return null;
        body = res.bodyBytes;
        await cache.storeLayer(book.id, body, sourceTag: sourceTag);
      } catch (_) {
        return null;
      }
    }
    try {
      // Decode off the UI isolate so large books don't jank the reader open.
      // Hand the encoded bytes to the isolate rather than the decoded string,
      // so the main isolate never holds a second (UTF-16) copy of the whole
      // JSON body alongside the isolate's own copy.
      final layer = await compute(_decodeTextLayer, body);
      cache.rememberLayer(book.id, layer);
      return layer;
    } catch (_) {
      return null;
    }
  }

  static TextLayer _decodeTextLayer(List<int> body) {
    final text = utf8.decode(body);
    return TextLayer.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  /// Downloads the raw PDF bytes for pdfrx page rendering. The presigned URL
  /// needs no auth header; on failure null is returned so the reader falls back
  /// to text-mode-only (paper + substituted font).
  ///
  /// When [bookId] is given the bytes are read from / written to the on-disk
  /// cache, and a stale cached copy is used as a fallback when the network
  /// fails (e.g. the presigned URL expired) so the book still opens.
  Future<Uint8List?> pdfBytes(String pdfUrl, {String? bookId}) async {
    final cache = BookContentCache.instance;
    final sourceTag = BookContentCache.sourceTagFrom(pdfUrl);
    if (bookId != null && await cache.isValidPdf(bookId, sourceTag: sourceTag)) {
      final cached = await cache.pdf(bookId);
      if (cached != null) return cached;
    }
    try {
      final res = await http
          .get(Uri.parse(pdfUrl))
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return _stalePdf(cache, bookId);
      final bytes = res.bodyBytes;
      if (bookId != null) {
        await cache.storePdf(bookId, bytes, sourceTag: sourceTag);
      }
      return bytes;
    } catch (_) {
      return _stalePdf(cache, bookId);
    }
  }

  /// Best-effort fallback to a stale cached copy of the PDF when the fresh
  /// download fails; returns null when there is nothing cached.
  Future<Uint8List?> _stalePdf(BookContentCache cache, String? bookId) async {
    if (bookId == null) return null;
    return cache.pdf(bookId);
  }

  // ------------------------------------------------- PDF renderer session

  /// Renderers stay alive for the session (shared across BooksService
  /// instances) so reopening a book skips the PDFium parse + page re-render.
  static const int _maxRenderers = 3;
  static final Map<String, PdfRenderer> _renderers = {};

  /// Returns the session renderer for [bookId], creating one when needed and
  /// evicting the least-recently-used entry past the cap.
  static PdfRenderer rendererFor(String bookId) {
    final existing = _renderers[bookId];
    if (existing != null) return existing;
    if (_renderers.length >= _maxRenderers) {
      final oldest = _renderers.keys.first;
      _renderers.remove(oldest)?.dispose();
    }
    final fresh = PdfRenderer();
    _renderers[bookId] = fresh;
    return fresh;
  }

  /// Drops every cached renderer (logout / account switch).
  static void clearRenderers() {
    for (final r in _renderers.values) {
      r.dispose();
    }
    _renderers.clear();
  }

  /// Highlights + notes for a book.
  Future<List<Annotation>> annotations(String bookId) async {
    final data = await api.get('/sync/annotations/$bookId');
    final items = data as List;
    return items
        .map((a) => Annotation.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Aggregated annotations across the whole library (the Notes tab).
  Future<Map<String, List<Annotation>>> allAnnotations() async {
    final books = await list();
    final entries = await Future.wait(books.map((b) async {
      try {
        final notes = await annotations(b.id);
        return MapEntry(b.id, notes);
      } catch (_) {
        return MapEntry(b.id, const <Annotation>[]);
      }
    }));
    final result = <String, List<Annotation>>{};
    for (final e in entries) {
      if (e.value.isNotEmpty) result[e.key] = e.value;
    }
    return result;
  }
}
