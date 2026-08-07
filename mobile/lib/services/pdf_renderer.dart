import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:pdfrx/pdfrx.dart';

/// Renders PDF pages to Flutter images via pdfrx (PDFium), the mobile mirror
/// of the web reader's pdf.js canvas. Pages are rendered on demand at the
/// requested pixel size and cached (LRU) so text-layer pages can show the real
/// PDF page behind the positioned runs in PDF mode.
class PdfRenderer {
  PdfDocument? _doc;
  final Map<int, ui.Image> _cache = {};
  final Map<int, int> _tick = {};
  final Set<int> _pending = {};
  int _clock = 0;
  int _pageCount = 0;

  static const int _cacheLimit = 10;

  /// Flips to true once a document is open, notifying page views (which listen
  /// while the reader opens the PDF in the background) that rendering can start.
  final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);

  int get pageCount => _pageCount;

  bool get isLoaded => _doc != null;

  /// Opens the PDF from raw bytes, replacing any previous document and
  /// discarding cached page images.
  Future<void> open(Uint8List bytes) async {
    final next = await PdfDocument.openData(
      bytes,
      sourceName: 'memory:reader.pdf',
      useProgressiveLoading: false,
    );
    final old = _doc;
    _doc = next;
    _pageCount = next.pages.length;
    if (old != null) {
      await old.dispose();
    }
    _clearCache();
    loaded.value = true;
  }

  /// Renders page [pageIndex] (0-based) at [width]x[height] device pixels and
  /// returns the image. Returns null when no document is open or rendering
  /// fails. The image is owned by this renderer's cache; do not dispose it.
  Future<ui.Image?> renderPage(
    int pageIndex,
    double width,
    double height,
  ) async {
    final doc = _doc;
    if (doc == null) return null;
    if (pageIndex < 0 || pageIndex >= _pageCount) return null;
    // Cap to a sane resolution so memory stays bounded on spreads.
    final scaleCap = math.min(1.0, 2000.0 / math.max(width, height));
    final pw = math.max(1, (width * scaleCap).round());
    final ph = math.max(1, (height * scaleCap).round());

    final key = pageIndex * 1_000_003 + pw * 7 + ph * 31;
    final hit = _cache[key];
    if (hit != null) {
      _tick[key] = ++_clock;
      return hit;
    }
    if (_pending.contains(key)) {
      // A render for this page/size is already in flight; poll briefly.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final ready = _cache[key];
        if (ready != null) return ready;
      }
      return null;
    }

    _pending.add(key);
    try {
      final page = doc.pages[pageIndex];
      final img = await page.render(
        fullWidth: pw.toDouble(),
        fullHeight: ph.toDouble(),
      );
      if (img == null) return null;
      final uiImage = await img.createImage();
      img.dispose();
      _cache[key] = uiImage;
      _tick[key] = ++_clock;
      _trimCache();
      return uiImage;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  /// The rendered page size in points for [pageIndex], used to build fallback
  /// page geometry when a book has no text layer. Null when unavailable.
  Future<({double width, double height})?> pageSize(int pageIndex) async {
    final doc = _doc;
    if (doc == null) return null;
    if (pageIndex < 0 || pageIndex >= _pageCount) return null;
    try {
      final page = doc.pages[pageIndex];
      await page.ensureLoaded();
      return (width: page.width, height: page.height);
    } catch (_) {
      return null;
    }
  }

  void _trimCache() {
    while (_cache.length > _cacheLimit) {
      int? oldest;
      var oldestTick = 1 << 62;
      for (final e in _tick.entries) {
        if (e.value < oldestTick) {
          oldestTick = e.value;
          oldest = e.key;
        }
      }
      if (oldest == null) break;
      _cache.remove(oldest)?.dispose();
      _tick.remove(oldest);
    }
  }

  void _clearCache() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
    _tick.clear();
    _pending.clear();
  }

  Future<void> dispose() async {
    loaded.value = false;
    _clearCache();
    await _doc?.dispose();
    _doc = null;
    _pageCount = 0;
  }
}
