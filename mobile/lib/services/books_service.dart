import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/annotation.dart';
import '../models/book.dart';
import 'api_client.dart';

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

  /// Reading position for a book (fraction 0..1 across the whole document).
  Future<double> progress(String bookId) async {
    final data = await api.get('/sync/progress/$bookId') as Map;
    final page = (data['current_page'] as num?)?.toDouble() ?? 0;
    final offset = (data['current_offset'] as num?)?.toDouble() ?? 0;
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

  Future<StructuredText?> structuredText(Book book) async {
    final url = book.structuredTextUrl;
    if (url == null) return null;
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 90)); // pre-signed URL, no auth
      if (res.statusCode != 200 || res.body.isEmpty) return null;
      // Decode off the UI isolate so large books don't jank the reader open.
      // Hand the encoded bytes to the isolate rather than the decoded string,
      // so the main isolate never holds a second (UTF-16) copy of the whole
      // JSON body alongside the isolate's own copy.
      return await compute(_decodeStructuredText, res.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  static StructuredText _decodeStructuredText(List<int> body) {
    final text = utf8.decode(body);
    return StructuredText.fromJson(jsonDecode(text) as Map<String, dynamic>);
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
