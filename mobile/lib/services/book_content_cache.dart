import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/book.dart';

/// On-disk + in-memory cache for a book's heavy content (raw PDF bytes + the
/// positioned text layer JSON), so reopening a book skips re-downloading
/// multi-MB presigned URLs and re-decoding the layer. Nothing here is required
/// for correctness: every read falls back to the network on a miss, and every
/// write is best-effort.
///
/// Files live under `<app support>/book_content/`:
///   {bookId}.pdf        raw PDF bytes for pdfrx
///   {bookId}.layer      structured-text JSON bytes (decoded in an isolate)
///   {bookId}.meta.json  {pdf_source_tag, layer_source_tag, fetched_at}
///
/// The PDF and the layer are tagged with *their own* source URL signature
/// (the text-layer and PDF presigned URLs differ), so each is validated
/// independently — otherwise the last write to the shared meta would invalidate
/// the other on the next open.
///
/// An entry is invalid when its source URL's stable path changes (a
/// re-extraction rewrites the object, so the URL path differs), when the app
/// explicitly invalidates (the reader's re-extract action), or after [maxAge].
/// The decoded layer is also kept in memory for the session so reopening a
/// book skips the multi-MB disk read + JSON decode entirely.
class BookContentCache {
  BookContentCache._();

  static final BookContentCache instance = BookContentCache._();

  static const Duration maxAge = Duration(days: 7);

  /// Cache capacity knobs: keep only the most recently touched books and cap
  /// total bytes so a big PDF library can't exhaust device storage.
  static const int _maxBooks = 6;
  static const int _maxBytes = 400 * 1024 * 1024;

  static const String _metaKey = '.meta.json';
  static const String _pdfSuffix = '.pdf';
  static const String _layerSuffix = '.layer';

  Directory? _dir;

  /// Decoded layers for the current session, keyed by book id. Kept small so a
  /// long reading session can't accumulate unbounded memory.
  final Map<String, TextLayer> _layerMemory = {};

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final d = Directory(
      '${base.path}${Platform.pathSeparator}book_content',
    );
    await d.create(recursive: true);
    return _dir = d;
  }

  /// A book id becomes a safe file name fragment.
  static String _safeName(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Stable signature of a presigned URL: scheme+authority+path, dropping the
  /// expiring query token so a re-extracted book (new path) invalidates cleanly.
  static String sourceTagFrom(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      final u = Uri.parse(url);
      return '${u.scheme}://${u.authority}${u.path}';
    } catch (_) {
      return url;
    }
  }

  Future<File> _entryFile(String bookId, String suffix) async {
    final dir = await _directory();
    return File(
      '${dir.path}${Platform.pathSeparator}${_safeName(bookId)}$suffix',
    );
  }

  /// Whether a fresh-enough, same-source PDF entry exists for [bookId]. The
  /// source tag comes from the book's current PDF presigned URL.
  Future<bool> isValidPdf(String bookId, {String? sourceTag}) async {
    final meta = await _meta(bookId);
    if (meta == null) return false;
    if (DateTime.now().difference(meta.fetchedAt) > maxAge) return false;
    if (sourceTag != null && meta.pdfSourceTag != sourceTag) return false;
    return true;
  }

  /// Whether a fresh-enough, same-source text-layer entry exists for [bookId].
  /// The source tag comes from the book's current structured-text URL.
  Future<bool> isValidLayer(String bookId, {String? sourceTag}) async {
    final meta = await _meta(bookId);
    if (meta == null) return false;
    if (DateTime.now().difference(meta.fetchedAt) > maxAge) return false;
    if (sourceTag != null && meta.layerSourceTag != sourceTag) return false;
    return true;
  }

  Future<Uint8List?> pdf(String bookId) async {
    final file = await _entryFile(bookId, _pdfSuffix);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> layer(String bookId) async {
    final file = await _entryFile(bookId, _layerSuffix);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// The decoded text layer from memory (session-only), or null.
  TextLayer? cachedLayer(String bookId) => _layerMemory[bookId];

  /// Keeps a decoded layer for the rest of the session so a re-open of the same
  /// book skips the disk read + isolate decode entirely.
  void rememberLayer(String bookId, TextLayer layer) {
    _layerMemory[bookId] = layer;
    if (_layerMemory.length > _maxBooks) {
      final oldest = _layerMemory.keys.first;
      _layerMemory.remove(oldest);
    }
  }

  Future<void> storePdf(
    String bookId,
    Uint8List bytes, {
    String? sourceTag,
  }) async {
    final file = await _entryFile(bookId, _pdfSuffix);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _touch(bookId, pdfSourceTag: sourceTag);
      await _prune();
    } catch (_) {
      // Cache is best-effort; the network path already produced the bytes.
    }
  }

  Future<void> storeLayer(
    String bookId,
    List<int> bytes, {
    String? sourceTag,
  }) async {
    final file = await _entryFile(bookId, _layerSuffix);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _touch(bookId, layerSourceTag: sourceTag);
      await _prune();
    } catch (_) {}
  }

  /// Drop a book's entry (re-extract action, corruption, logout), including
  /// its in-memory decoded layer.
  Future<void> invalidate(String bookId) async {
    _layerMemory.remove(bookId);
    for (final suffix in [_pdfSuffix, _layerSuffix, _metaKey]) {
      try {
        final f = await _entryFile(bookId, suffix);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ internals

  Future<_Meta?> _meta(String bookId) async {
    final file = await _entryFile(bookId, _metaKey);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final fetchedAt = DateTime.tryParse(raw['fetched_at'] as String? ?? '');
      if (fetchedAt == null) return null;
      // Migration: metas written before the per-content tags existed carried a
      // single `source_tag` and an `extraction_status`. Treat it as valid for
      // both contents so cached books don't re-download after an upgrade.
      final legacy = raw['source_tag'] as String? ?? '';
      return _Meta(
        fetchedAt: fetchedAt,
        pdfSourceTag: raw['pdf_source_tag'] as String? ?? legacy,
        layerSourceTag: raw['layer_source_tag'] as String? ?? legacy,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes the meta with the given per-content source tags. Each store call
  /// updates only its own tag, so the PDF tag never clobbers the layer tag
  /// (and vice versa). Missing tags keep their previous value.
  Future<void> _touch(
    String bookId, {
    String? pdfSourceTag,
    String? layerSourceTag,
  }) async {
    final existing = await _meta(bookId);
    final file = await _entryFile(bookId, _metaKey);
    await file.writeAsString(
      jsonEncode({
        'pdf_source_tag': pdfSourceTag ?? existing?.pdfSourceTag ?? '',
        'layer_source_tag': layerSourceTag ?? existing?.layerSourceTag ?? '',
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _prune() async {
    try {
      final dir = await _directory();
      final entries = <_Meta, String>{};
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith(_metaKey)) continue;
        try {
          final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final fetchedAt = DateTime.tryParse(raw['fetched_at'] as String? ?? '');
          if (fetchedAt == null) continue;
          entries[_Meta(
            fetchedAt: fetchedAt,
            pdfSourceTag: raw['pdf_source_tag'] as String? ?? '',
            layerSourceTag: raw['layer_source_tag'] as String? ?? '',
          )] = f.path.substring(0, f.path.length - _metaKey.length);
        } catch (_) {}
      }
      final sorted = entries.entries.toList()
        ..sort((a, b) => a.key.fetchedAt.compareTo(b.key.fetchedAt));
      while (sorted.length > _maxBooks) {
        final oldest = sorted.removeAt(0);
        await _deleteEntry(oldest.value);
      }
      var total = 0;
      await for (final f in dir.list()) {
        if (f is File) total += await f.length();
      }
      if (total > _maxBytes) {
        for (final e in sorted) {
          if (total <= _maxBytes) break;
          final before = await _entrySize(e.value);
          await _deleteEntry(e.value);
          total -= before;
        }
      }
    } catch (_) {}
  }

  Future<int> _entrySize(String base) async {
    var total = 0;
    for (final suffix in [_pdfSuffix, _layerSuffix, _metaKey]) {
      final f = File('$base$suffix');
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  Future<void> _deleteEntry(String base) async {
    for (final suffix in [_pdfSuffix, _layerSuffix, _metaKey]) {
      try {
        final f = File('$base$suffix');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

class _Meta {
  final DateTime fetchedAt;
  final String pdfSourceTag;
  final String layerSourceTag;

  const _Meta({
    required this.fetchedAt,
    required this.pdfSourceTag,
    required this.layerSourceTag,
  });
}
