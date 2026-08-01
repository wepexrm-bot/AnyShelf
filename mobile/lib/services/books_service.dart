import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/annotation.dart';
import '../models/book.dart';
import 'api_client.dart';

class BooksService {
  final ApiClient api;
  BooksService({ApiClient? api}) : api = api ?? ApiClient();

  Future<List<Book>> list() async {
    final data = await api.get('/books/');
    final items = data as List;
    return items.map((b) => Book.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<Book> get(String id) async {
    final data = await api.get('/books/$id');
    return Book.fromJson(data as Map<String, dynamic>);
  }

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
      return StructuredText.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
