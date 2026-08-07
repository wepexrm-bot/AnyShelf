import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/pdf_renderer.dart';

/// A highlight range on a page: char offsets within the page run stream plus a
/// color. Mirrors the shared `{page,start_char,end_char}` anchor contract.
class PageHighlight {
  final int start;
  final int end;
  final Color color;
  const PageHighlight({required this.start, required this.end, required this.color});
}

/// A single run laid out for painting: cached TextPainter plus the per-line
/// scaleX so the run stretches to its intended advance width.
class _RLayout {
  final TextRun run;
  final TextPainter tp;
  final double scaleX; // rendered width / painter width
  final double x; // rendered left edge
  final double top; // rendered top edge

  const _RLayout({
    required this.run,
    required this.tp,
    required this.scaleX,
    required this.x,
    required this.top,
  });

  double get bottom => top + tp.height;

  /// Precise painted boxes for the [from,to) substring of this run (unscaled
  /// painter coordinates), each transformed into widget space.
  List<Rect> boxesFor(int from, int to) {
    if (tp.width <= 0) return const [];
    final lo = math.max(from, 0);
    final hi = math.min(to, run.t.length);
    if (hi <= lo) return const [];
    final boxes = tp.getBoxesForSelection(
      TextSelection(baseOffset: lo, extentOffset: hi),
    );
    if (boxes.isEmpty) return const [];
    return boxes.map((b) {
      return Rect.fromLTRB(
        x + b.left * scaleX,
        top + b.top,
        x + b.right * scaleX,
        top + b.bottom,
      );
    }).toList();
  }

  /// The run's painted bounds (whole run).
  Rect get bounds => Rect.fromLTRB(
        x,
        top,
        x + tp.width * scaleX,
        bottom,
      );
}

/// Renders one positioned text-layer page at a fixed pixel width, preserving
/// the PDF page's aspect ratio. Runs are drawn with per-line scaleX so the
/// PDF's native layout is reproduced faithfully (the mobile mirror of the
/// extraction-lab reader's text layer).
///
/// In **text mode** (theme.textMode on, non-image page) the page is drawn on
/// themed paper with the substituted font. In **PDF mode** (text mode off or
/// an image/cover page) the real PDF page rendered by [pdf] is shown behind
/// the runs, which stay transparent but keep hit-testing/selection working.
class TextLayerPageView extends StatefulWidget {
  final TextLayerPage page;
  final double renderWidth;
  final ReaderSettings settings;
  final Color paper;

  /// Renderer for the real PDF page; null disables PDF mode (paper only).
  final PdfRenderer? pdf;

  final List<PageHighlight> highlights;

  /// Called when the user long-presses a word. [start]/[end] are char offsets
  /// into the page run stream, [text] is the word, [rect] its painted bounds.
  final void Function(Offset global, Rect rect, int start, int end, String text)?
      onWordLongPress;

  const TextLayerPageView({
    super.key,
    required this.page,
    required this.renderWidth,
    required this.settings,
    required this.paper,
    this.pdf,
    this.highlights = const [],
    this.onWordLongPress,
  });

  @override
  State<TextLayerPageView> createState() => _TextLayerPageViewState();
}

class _TextLayerPageViewState extends State<TextLayerPageView> {
  static final Map<int, List<_RLayout>> _cache = {};
  static final Map<int, String> _cacheKey = {};

  ui.Image? _pageImage;

  /// True when the substituted-font layer is actually painted over paper —
  /// mirrors the web reader's `effectiveTextMode = textMode && hasText &&
  /// !pageHasImage`. Image pages (covers/illustrations) always show the real
  /// page so the artwork isn't lost in text mode.
  bool get _effectiveTextMode =>
      widget.settings.textMode &&
      widget.page.runs.isNotEmpty &&
      !widget.page.hasImage;

  void _onPdfLoaded() {
    // The reader opens the PDF in the background; when it lands, any page
    // waiting on the real page image (PDF mode / image pages) re-renders.
    if (!mounted) return;
    final pdf = widget.pdf;
    if (pdf == null || !pdf.loaded.value) return;
    _maybeRenderPageImage();
  }

  List<_RLayout> get _layouts {
    final key = _buildKey();
    final cached = _cache[widget.page.page];
    if (cached != null && _cacheKey[widget.page.page] == key) return cached;
    final layouts = _computeLayouts();
    _cache[widget.page.page] = layouts;
    _cacheKey[widget.page.page] = key;
    if (_cache.length > 40) {
      // Evicted entries are dropped (the GC collects their TextPainters) rather
      // than disposed: the cache is shared statically and a page being evicted
      // may still be painted by a live widget, so its painter must not die.
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _cacheKey.remove(oldest);
    }
    return layouts;
  }

  double get _scale =>
      widget.page.width <= 0 ? 1 : widget.renderWidth / widget.page.width;

  TextStyle _styleFor(TextRun r) {
    final base = _resolveReaderFont(
      widget.settings.fontFamily,
      TextStyle(
        fontSize: r.fs * _scale,
        color: widget.settings.atmosphere.text,
      ),
    );
    return base.copyWith(
      fontWeight: r.isBold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: r.isItalic ? FontStyle.italic : FontStyle.normal,
    );
  }

  /// Resolves a reader font family without ever throwing: google_fonts is
  /// missing a few families (e.g. OpenDyslexic), so an unknown one falls back
  /// to the plain family name instead of breaking the page render.
  static TextStyle _resolveReaderFont(String family, TextStyle base) {
    try {
      return GoogleFonts.getFont(family, textStyle: base);
    } catch (_) {
      return base.copyWith(fontFamily: family);
    }
  }

  String _buildKey() {
    final s = widget.settings;
    return '${s.fontFamily}|${s.atmosphere.id}|'
        '${widget.renderWidth.toStringAsFixed(2)}|'
        '${widget.page.width.toStringAsFixed(2)}|'
        '${widget.page.height.toStringAsFixed(2)}|'
        '${s.textMode}|${widget.page.hasImage}';
  }

  List<_RLayout> _computeLayouts() {
    final out = <_RLayout>[];
    for (final r in widget.page.runs) {
      if (r.t.isEmpty) continue;
      final style = _styleFor(r);
      final tp = TextPainter(
        text: TextSpan(text: r.t, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      if (tp.width <= 0) {
        tp.dispose();
        continue;
      }
      final targetW = r.w * _scale;
      final scaleX = targetW > 0 && tp.width > 0
          ? (targetW / tp.width).clamp(0.05, 6.0)
          : 1.0;
      out.add(_RLayout(
        run: r,
        tp: tp,
        scaleX: scaleX,
        x: r.x * _scale,
        top: (r.y - r.fs) * _scale,
      ));
    }
    return out;
  }

  /// Locates the word whose painted bounds contain [local], returning char
  /// offsets + text, or null.
  ({int start, int end, String text, Rect rect})? hitTestWord(Offset local) {
    final x = local.dx;
    final y = local.dy;
    _RLayout? nearest;
    var best = double.infinity;
    for (final l in _layouts) {
      if (y < l.top - l.tp.height * 0.4 || y > l.bottom + l.tp.height * 0.4) {
        continue;
      }
      final d = (x - l.x).abs();
      if (d < best) {
        best = d;
        nearest = l;
      }
    }
    if (nearest == null) return null;
    // Map back to the run's painter coordinate space (undo the scaleX).
    final px = (x - nearest.x) / nearest.scaleX;
    final pos = nearest.tp.getPositionForOffset(Offset(px, nearest.tp.height / 2));
    final offset = pos.offset.clamp(0, nearest.run.t.length);
    final text = nearest.run.t;
    var ws = offset;
    var we = offset;
    while (ws > 0 && text[ws - 1] != ' ' && text[ws - 1] != '\n' && text[ws - 1] != '\t') {
      ws--;
    }
    while (we < text.length && text[we] != ' ' && text[we] != '\n' && text[we] != '\t') {
      we++;
    }
    if (we <= ws) {
      ws = offset;
      we = math.min(offset + 1, text.length);
    }
    // The word's painted box: re-measure only the word span via the painter.
    final wordRects = nearest.boxesFor(ws, we);
    final rect = wordRects.isNotEmpty ? wordRects.first : nearest.bounds;
    return (
      start: nearest.run.start + ws,
      end: nearest.run.start + we,
      text: text.substring(ws, we),
      rect: rect,
    );
  }

  @override
  void initState() {
    super.initState();
    // Defer to after initState so MediaQuery is safe to read; the first frame
    // paints the plain page, then the PDF image swaps in asynchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeRenderPageImage();
    });
    widget.pdf?.loaded.addListener(_onPdfLoaded);
  }

  @override
  void didUpdateWidget(covariant TextLayerPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdf != widget.pdf) {
      oldWidget.pdf?.loaded.removeListener(_onPdfLoaded);
      widget.pdf?.loaded.addListener(_onPdfLoaded);
    }
    if (oldWidget.renderWidth != widget.renderWidth ||
        oldWidget.pdf != widget.pdf ||
        oldWidget.settings.textMode != widget.settings.textMode ||
        oldWidget.page.hasImage != widget.page.hasImage) {
      _pageImage = null;
      _maybeRenderPageImage();
    }
  }

  /// Renders the real PDF page when PDF mode is active (text mode off, or the
  /// page carries an image). Runs stay painted/transparent for selection.
  Future<void> _maybeRenderPageImage() async {
    final pdf = widget.pdf;
    if (pdf == null || _effectiveTextMode) {
      setState(() => _pageImage = null);
      return;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = (widget.renderWidth * dpr).round();
    final h = (widget.page.height * (widget.renderWidth / widget.page.width) * dpr)
        .round();
    final img = await pdf.renderPage(widget.page.page, w.toDouble(), h.toDouble());
    if (!mounted || !identical(widget.pdf, pdf)) return;
    setState(() => _pageImage = img);
  }

  void _onLongPress(LongPressStartDetails d) {
    final hit = hitTestWord(d.localPosition);
    if (hit == null) return;
    widget.onWordLongPress?.call(
      d.globalPosition,
      hit.rect,
      hit.start,
      hit.end,
      hit.text,
    );
  }

  @override
  void dispose() {
    // The layout cache is static and shared by every widget for the same page
    // index, so a disposed page must NOT dispose its TextPainters or drop the
    // entry: a same-index sibling (e.g. its replacement during a page jump)
    // may still be painting with them. Entries are replaced/evicted in
    // [_layouts] only.
    widget.pdf?.loaded.removeListener(_onPdfLoaded);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.renderWidth;
    final h = widget.page.height * (w / widget.page.width);
    final layouts = _layouts;
    final highlights = widget.highlights;

    return SizedBox(
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: _onLongPress,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _TextLayerPainter(
              layouts: layouts,
              highlights: highlights,
              textColor: widget.settings.atmosphere.text,
              paper: widget.paper,
              pageImage: _pageImage,
              paintRuns: _effectiveTextMode,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextLayerPainter extends CustomPainter {
  final List<_RLayout> layouts;
  final List<PageHighlight> highlights;
  final Color textColor;
  final Color paper;
  final ui.Image? pageImage;
  final bool paintRuns;

  _TextLayerPainter({
    required this.layouts,
    required this.highlights,
    required this.textColor,
    required this.paper,
    this.pageImage,
    this.paintRuns = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Page paper background.
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);

    // The real PDF page (PDF mode / image pages). In text mode this is null
    // and the substituted-font layer is painted on the paper instead.
    final img = pageImage;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // Highlight rectangles behind the runs (precise sub-run boxes).
    final hlPaint = Paint();
    for (final hl in highlights) {
      hlPaint.color = hl.color.withValues(alpha: 0.45);
      for (final l in layouts) {
        if (l.run.end <= hl.start || l.run.start >= hl.end) continue;
        final boxes = l.boxesFor(hl.start - l.run.start, hl.end - l.run.start);
        for (final b in boxes) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(b, const Radius.circular(2)),
            hlPaint,
          );
        }
      }
    }

    // Text runs, each scaled on X to its advance width. Skipped when the real
    // page is visible (runs stay only for hit-testing/selection).
    if (!paintRuns) return;
    for (final l in layouts) {
      canvas.save();
      canvas.translate(l.x, l.top);
      canvas.scale(l.scaleX, 1.0);
      l.tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TextLayerPainter oldDelegate) =>
      oldDelegate.layouts != layouts ||
      oldDelegate.highlights != highlights ||
      oldDelegate.textColor != textColor ||
      oldDelegate.paper != paper ||
      oldDelegate.pageImage != pageImage ||
      oldDelegate.paintRuns != paintRuns;
}
