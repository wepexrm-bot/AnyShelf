import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  /// Uploads a PDF file with metadata. Returns the uploaded book payload.
  Future<Map<String, dynamic>> upload({
    required String filePath,
    required String title,
    required String author,
    String? genre,
  }) async {
    final files = <http.MultipartFile>[
      await http.MultipartFile.fromPath('file', filePath),
    ];
    final data = await api.postMultipart('/books/upload', fields: {
      'title': title,
      'author': author,
      if (genre != null && genre.isNotEmpty) 'genre': genre,
    }, files: files);
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
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

  /// Reading position for a book (fraction 0..1 across the whole document).
  Future<double> progress(String bookId) async {
    final data = await api.get('/sync/progress/$bookId') as Map;
    final page = (data['current_page'] as num?)?.toDouble() ?? 0;
    final offset = (data['current_offset'] as num?)?.toDouble() ?? 0;
    // current_offset carries the overall fraction; fall back to the page number.
    return offset > 0 ? offset : page;
  }

  Future<void> saveProgress(String bookId,
      {double? fraction, double? page}) async {
    await api.post('/sync/progress', body: {
      'book_id': bookId,
      'current_page': page ?? 0,
      'current_offset': fraction ?? 0,
    });
  }

  Future<StructuredText?> structuredText(Book book) async {
    final url = book.structuredTextUrl;
    if (url == null) return null;
    final res = await http.get(Uri.parse(url)); // pre-signed URL, no auth
    if (res.statusCode != 200 || res.body.isEmpty) return null;
    try {
      // Decode off the UI isolate so large books don't jank the reader open.
      return await compute(_decodeStructuredText, res.body);
    } catch (_) {
      return null;
    }
  }

  static StructuredText _decodeStructuredText(String body) =>
      StructuredText.fromJson(jsonDecode(body) as Map<String, dynamic>);

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
    final result = <String, List<Annotation>>{};
    for (final b in books) {
      try {
        final notes = await annotations(b.id);
        if (notes.isNotEmpty) result[b.id] = notes;
      } catch (_) {}
    }
    return result;
  }
}
