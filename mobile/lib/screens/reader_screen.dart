import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/annotation.dart';
import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/book_content_cache.dart';
import '../services/books_service.dart';
import '../services/library_refresh.dart';
import '../services/pdf_renderer.dart';
import '../services/settings_service.dart';
import '../theme/reader_atmosphere.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/text_layer_page_view.dart';
import 'reader_appearance_sheet.dart';

/// The immersive reader. Renders the positioned text layer (physical PDF pages
/// with per-line scaleX runs) over the real PDF page rendered by pdfrx, in
/// scroll or paginated mode, with highlights, notes, bookmarks, TOC, search,
/// and reading progress. PDF mode shows the real page; text mode substitutes
/// the chosen font on themed paper.
class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _booksService = BooksService();
  final _settingsService = SettingsService();
  final _readingKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  late ReaderSettings _settings = ReaderSettings.defaults();
  TextLayer? _layer;
  /// Session-persistent per-book renderer (see BooksService.rendererFor), so
  /// reopening a book skips the PDFium parse and keeps the page image cache.
  PdfRenderer get _pdfRenderer => BooksService.rendererFor(widget.book.id);
  bool _uiVisible = false;
  bool _bookmarked = false;
  String? _bookmarkId; // backend annotation id of the current bookmark, if any
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;
  ReaderSettings? _pendingSettings;

  // Text-extraction status: while a freshly uploaded book is still being
  // processed the text layer isn't ready, so we show a looping extraction
  // animation and poll until the backend reports "done".
  String? _extractionStatus;
  double? _extractionProgress;
  Timer? _extractionTimer;

  // highlight state: per physical page, char-range highlights.
  Map<int, List<PageHighlight>> _highlightsByPage = {};
  _HighlightMenuState? _highlightMenu;

  // In-reader "go to page" panel. Deliberately NOT a Navigator route: a route
  // pop deactivates its Overlay entry while the jump's rebuild runs, which can
  // trip the framework's `InheritedElement._dependents.isEmpty` assertion.
  bool _goToPageOpen = false;
  final TextEditingController _goToPageController = TextEditingController();

  // Set when the scroll list should re-position itself to the current reading
  // progress next time it builds (e.g. switching paginated -> scroll).
  bool _restoreScrollOnShow = false;

  // True while the scroll view is still landing on its restored position, so
  // the intermediate scroll notification from the jump doesn't overwrite the
  // saved position on the server before the restore completes.
  bool _restoringScroll = false;

  // Annotations loaded from the backend, cached for the panel.
  List<Annotation>? _annotations;

  // page tracking (physical pages, 0-based index)
  int _currentPage = 0;
  int _pageCount = 0;

  // Bumped on every mode switch so the paginated view remounts onto the
  // current page instead of reusing stale state.
  int _anchorSeed = 0;

  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

  double get _progress => _progressNotifier.value;

  // Text-layer reading is available when the positioned layer loaded and has
  // at least one run (legacy reflow JSON has no runs, so those books fall back
  // to the fixed PDF until they are re-extracted).
  bool get _textLayerAvailable => _layer?.hasRuns ?? false;

  /// Pages to render: the positioned text layer's pages when present, else
  /// fallback pages synthesised from the PDF itself (scanned / run-less books,
  /// where PDF mode shows the real page behind an empty text layer).
  List<TextLayerPage> get _renderPages =>
      (_layer?.pages.isNotEmpty ?? false) ? _layer!.pages : _fallbackPages;

  List<TextLayerPage> _fallbackPages = const [];

  /// Builds fallback page geometry from the opened PDF when a book has no
  /// text layer (run-less pages still render in PDF mode via pdfrx).
  Future<void> _buildFallbackPages() async {
    final count = _pdfRenderer.pageCount;
    if (count == 0) return;
    final list = <TextLayerPage>[];
    for (var i = 0; i < count; i++) {
      final sz = await _pdfRenderer.pageSize(i);
      if (sz == null) return;
      list.add(TextLayerPage(
        page: i,
        width: sz.width,
        height: sz.height,
        rotation: 0,
        hasImage: true,
        runs: const [],
      ));
    }
    if (!mounted) return;
    setState(() => _fallbackPages = list);
  }

  /// True while the book's text is still being extracted and the text layer
  /// isn't ready yet. Drives the looping extraction animation.
  bool get _isExtracting =>
      _layer == null &&
      _extractionStatus != 'done' &&
      _extractionStatus != 'failed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flushProgressSave();
    _flushSettingsSave();
    _extractionTimer?.cancel();
    _goToPageController.dispose();
    _paginateController?.dispose();
    _scrollController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  /// Persist a debounced settings save that hadn't fired yet, so the last
  /// appearance/mode change is never lost to the 400ms debounce timer.
  void _flushSettingsSave() {
    _saveTimer?.cancel();
    final pending = _pendingSettings;
    _pendingSettings = null;
    if (pending != null) {
      _settingsService.save(pending);
    }
  }

  /// Persist the current reading position immediately, cancelling any pending
  /// debounced save. Called when leaving the reader so progress is never lost
  /// to the debounce timer.
  void _flushProgressSave() {
    if (_restoringScroll) return;
    if (_progress > 0) {
      unawaited(_saveProgressNow());
    }
  }

  /// Saves the current reading position to the backend, ignoring transient
  /// failures so an offline/backed-up save can never surface as an unhandled
  /// exception. The local snapshot is always updated regardless.
  Future<void> _saveProgressNow() async {
    try {
      await _booksService.saveProgress(widget.book.id, fraction: _progress);
    } catch (_) {
      // Transient or offline failure: the position just isn't persisted yet.
    }
    LibraryRefresh.instance.applyProgress(widget.book.id, _progress);
  }

  Future<void> _whenReaderFontLoaded() async {
    // Accessing the reader styles registers the load with google_fonts'
    // pending set, so pendingFonts() below actually waits for it.
    // ignore: unnecessary_statements
    _bodyStyle;
    try {
      await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 6));
    } catch (_) {
      // Offline / slow network: the fallback font is used for both measurement
      // and rendering, so layout stays self-consistent.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await _booksService.get(widget.book.id);
      final (settings, bookmark, progress, layer) = await (
        _settingsService.fetch(),
        _loadBookmark(),
        _booksService.progress(widget.book.id).onError((_, __) => 0.0),
        detail.structuredTextUrl != null
            ? _booksService.textLayer(detail)
            : Future<TextLayer?>.value(null),
      ).wait;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _layer = layer;
        _extractionStatus = detail.extractionStatus;
        _progressNotifier.value = progress;
        _bookmarked = bookmark != null;
        _bookmarkId = bookmark;
        _pageCount = layer?.pages.length ?? 0;
      });
      final hasLayer = (layer?.pages.isNotEmpty ?? false);
      if (hasLayer) {
        // The text pages are ready: wait for the reading font so run
        // measurements use the real family, then paint immediately. The real
        // PDF opens in the background so PDF-mode / image pages swap in when it
        // lands -- the reader never waits on the PDF to start reading.
        await _whenReaderFontLoaded();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _zoom = 1.0;
          if (progress > 0 && _settings.mode == ReaderMode.singlePage) {
            _currentPage = _pageForFraction(progress);
          }
        });
        _openPdfInBackground(detail.pdfUrl);
      } else {
        // No text layer (scanned / legacy reflow): the fallback page geometry
        // comes from the PDF itself, so it must open before pages exist.
        final bytes = await _pdfBytesFor(detail.pdfUrl);
        if (!mounted) return;
        if (bytes != null && bytes.isNotEmpty) {
          await _pdfRenderer.open(bytes);
        }
        await _buildFallbackPages();
        if (!mounted) return;
        await _whenReaderFontLoaded();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _zoom = 1.0;
          if (progress > 0 && _settings.mode == ReaderMode.singlePage) {
            _currentPage = _pageForFraction(progress);
          }
        });
      }
      if (_settings.mode == ReaderMode.scroll && progress > 0) {
        _restoreScrollOnShow = true;
      }
      _maybeExtractPoll();
      _applySavedHighlights();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Downloads (or reads from cache) the raw PDF bytes for the reader.
  Future<Uint8List?> _pdfBytesFor(String? pdfUrl) async {
    if (pdfUrl == null || pdfUrl.isEmpty) return null;
    return _booksService.pdfBytes(pdfUrl, bookId: widget.book.id);
  }

  /// Opens the real PDF without blocking the reader: text pages are already
  /// painted (paper + substituted font), and pages waiting on the real page
  /// image re-render when [PdfRenderer.loaded] flips.
  Future<void> _openPdfInBackground(String? pdfUrl) async {
    try {
      final bytes = await _pdfBytesFor(pdfUrl);
      if (!mounted || bytes == null || bytes.isEmpty) return;
      await _pdfRenderer.open(bytes);
      if (mounted) setState(() {});
    } catch (_) {
      // Text mode keeps the book fully readable; a PDF failure only costs the
      // real-page backdrop for image / PDF-mode pages.
    }
  }

  void _maybeExtractPoll() {
    if (_layer != null) {
      _extractionTimer?.cancel();
      _extractionTimer = null;
      return;
    }
    if (_extractionStatus == 'done' || _extractionStatus == 'failed') {
      _extractionTimer?.cancel();
      _extractionTimer = null;
      return;
    }
    _extractionTimer?.cancel();
    _extractionTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollExtraction());
  }

  Future<void> _pollExtraction() async {
    try {
      final r = await _booksService.extractionStatus(widget.book.id);
      if (!mounted) return;
      setState(() {
        _extractionStatus = r.status;
        _extractionProgress = r.progress;
      });
      if (r.status == 'done') {
        _extractionTimer?.cancel();
        await _load();
      } else if (r.status == 'failed') {
        _extractionTimer?.cancel();
      }
    } catch (_) {
      // Transient poll error (backend between reloads etc.) -- keep polling.
    }
  }

  void _updateSettings(ReaderSettings next) {
    final modeChanged = next.mode != _settings.mode;
    if (modeChanged) {
      // The paginated view remounts onto the current page on switch.
      _anchorSeed++;
    }
    setState(() {
      _settings = next;
      if (next.mode == ReaderMode.scroll) _restoreScrollOnShow = true;
      if (modeChanged) _zoom = 1.0;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _pendingSettings = null;
      _settingsService.save(next);
    });
    _pendingSettings = next;
  }

  /// Toggles between text mode (substituted font on themed paper) and PDF mode
  /// (the real page rendered by pdfrx). Persisted locally, like the web
  /// reader's `reader_textmode` preference.
  void _toggleTextMode() {
    setState(() => _settings = _settings.copyWith(textMode: !_settings.textMode));
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('reader_textmode', _settings.textMode),
    );
  }

  /// Triggers a backend re-extraction of the book's text layer, then reloads
  /// the layer (and the PDF) so newly added fields like `has_image` appear.
  /// Mirrors the web reader's re-extract button.
  Future<void> _reExtract() async {
    setState(() {
      _extractionStatus = 'processing';
      _extractionProgress = 0;
      _layer = null;
      _fallbackPages = const [];
    });
    // The backend is about to produce a new layer + PDF; drop the stale copies
    // so the reload after extraction can't serve old content from disk.
    await BookContentCache.instance.invalidate(widget.book.id);
    _maybeExtractPoll();
    try {
      await _booksService.reExtract(widget.book.id);
    } catch (_) {
      // The status poll below reflects the real state; a failure here is fine.
    }
  }

  Future<String?> _loadBookmark() async {
    try {
      final notes = await _booksService.annotations(widget.book.id);
      for (final a in notes) {
        if (a.kind == 'bookmark') return a.id;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkId != null) {
      final id = _bookmarkId;
      setState(() {
        _bookmarked = false;
        _bookmarkId = null;
      });
      if (id != null) {
        await _booksService.api.delete('/sync/annotations/$id');
      }
      return;
    }
    setState(() => _bookmarked = true);
    try {
      final res = await _booksService.api
          .post('/sync/annotations', body: {
        'book_id': widget.book.id,
        'kind': 'bookmark',
        'anchor': 'Page ${_currentPage + 1}',
      });
      if (res is Map && res['id'] != null) {
        if (!mounted) return;
        setState(() => _bookmarkId = res['id'] as String);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _bookmarked = false);
    }
  }

  /// Parse a char-range anchor `{page,start_char,end_char}` if present.
  ({int page, int start, int end})? _parseCharAnchor(String? anchor) {
    if (anchor == null || !anchor.startsWith('{')) return null;
    try {
      final m = jsonDecode(anchor);
      if (m is Map &&
          m['page'] is int &&
          m['start_char'] is int &&
          m['end_char'] is int) {
        return (
          page: m['page'] as int,
          start: m['start_char'] as int,
          end: m['end_char'] as int,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Reconcile saved annotations (user highlights + imported PDF highlights)
  /// into per-page char ranges so they render in both scroll and paginated
  /// modes without requiring the user to re-select them.
  Future<void> _applySavedHighlights() async {
    final anns = await _loadAnnotations();
    final byPage = <int, List<PageHighlight>>{};
    for (final a in anns) {
      if (a.kind != 'highlight') continue;
      final color = _parseColor(
        a.color ?? (a.importedFromPdf ? '#8BC34A' : '#FFD54F'),
        fallback: _settings.atmosphere.accent,
      );
      final parsed = _parseCharAnchor(a.anchor);
      if (parsed != null && parsed.page >= 0 && parsed.page < (_layer?.pages.length ?? 0)) {
        byPage
            .putIfAbsent(parsed.page, () => [])
            .add(PageHighlight(start: parsed.start, end: parsed.end, color: color));
        continue;
      }
      final text = a.anchoredText;
      if (text == null || text.isEmpty) continue;
      for (var p = 0; p < (_layer?.pages.length ?? 0); p++) {
        final idx = _layer!.pages[p].text.indexOf(text);
        if (idx >= 0) {
          byPage
              .putIfAbsent(p, () => [])
              .add(PageHighlight(start: idx, end: idx + text.length, color: color));
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() => _highlightsByPage = byPage);
  }

  Future<List<Annotation>> _loadAnnotations() async {
    if (_annotations != null) return _annotations!;
    try {
      _annotations = await _booksService.annotations(widget.book.id);
    } catch (_) {
      _annotations = const [];
    }
    return _annotations!;
  }

  Future<void> _openAnnotations() async {
    final anns = await _loadAnnotations();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnotationsSheet(
        annotations: anns,
        atmosphere: _settings.atmosphere,
        canTap: _textLayerAvailable,
        onTapHighlight: _scrollToAnnotatedText,
      ),
    );
  }

  void _scrollToAnnotatedText(String text) {
    if (!_textLayerAvailable) return;
    for (var p = 0; p < _layer!.pages.length; p++) {
      if (_layer!.pages[p].text.contains(text)) {
        _jumpToPage(p);
        return;
      }
    }
  }

  /// Jump to a physical page (0-based) in whichever mode is active.
  void _jumpToPage(int page) {
    final idx = page.clamp(0, math.max(0, _renderPages.length - 1)).toInt();
    setState(() => _currentPage = idx);
    _onPageShown(idx);
    if (_settings.mode == ReaderMode.singlePage) {
      if (_paginateController?.hasClients ?? false) {
        // Defer the actual jump to the end of the frame: jumpToPage fires
        // `onPageChanged` synchronously (a second setState), so running it
        // post-frame keeps that churn out of any in-progress element
        // deactivation the current frame is walking.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (_paginateController?.hasClients ?? false)) {
            _paginateController!.jumpToPage(idx);
          }
        });
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _restoreScrollToTarget(_scrollOffsetForPage(idx));
        }
      });
    }
  }

  double get _fontSize => _settings.fontSize;

  /// Resolves a reader font family to a [TextStyle] without ever throwing:
  /// google_fonts covers most families, but its bundled directory is missing a
  /// few (e.g. OpenDyslexic), so an unknown family falls back to the plain
  /// family name instead of blocking the book from opening.
  static TextStyle _resolveReaderFont(String family, TextStyle base) {
    try {
      return GoogleFonts.getFont(family, textStyle: base);
    } catch (_) {
      return base.copyWith(fontFamily: family);
    }
  }

  TextStyle get _bodyStyle => _resolveReaderFont(
        _settings.fontFamily,
        TextStyle(
          fontSize: _fontSize,
          color: _settings.atmosphere.text,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loading = _loading;
    final error = _error;
    // The keyed Stack stays mounted in every state (loading / error / reading)
    // so the GlobalKey'd subtree is never deactivated and re-created, which
    // trips the framework's GlobalKey retake machinery (see the framework.dart
    // `_InactiveElements` assertion). Loading and error render as inner
    // children; the chrome is hidden while they're shown.
    return Scaffold(
      backgroundColor: _settings.atmosphere.background,
      body: Stack(
        key: _readingKey,
        children: [
          if (loading)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            Positioned.fill(child: _errorView())
          else ...[
            Positioned.fill(child: _readingSurface()),
            if (_highlightMenu != null) _buildHighlightMenu(),
            _buildTopBar(),
            _buildBottomBar(),
            _buildGoToPagePanel(),
          ],
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Couldn\'t open this book',
                style: SereneType.title.copyWith(
                    color: _settings.atmosphere.text)),
            const SizedBox(height: 8),
            Text('$_error',
                textAlign: TextAlign.center,
                style: SereneType.uiBody
                    .copyWith(color: _settings.atmosphere.text)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  void _toggleChrome() {
    setState(() {
      _uiVisible = !_uiVisible;
      _highlightMenu = null;
    });
  }

  // ---------------------------------------------------------------- surface

  Widget _readingSurface() {
    if (_isExtracting) return _extractionView();
    if (_renderPages.isEmpty) return _fixedPdfUnavailableView();
    // The base surface (scroll list / PageView) stays mounted at all times and
    // the zoom overlay floats above it. Keeping the surface in a stable tree
    // slot preserves its exact scroll/paginate position, so zooming in and out
    // never lands on a different page. The overlay itself is also kept mounted
    // (gated by IgnorePointer/Opacity) so its render object is always laid out
    // and reliably receives gestures the moment zoom is entered.
    return Stack(
      fit: StackFit.expand,
      children: [
        _settings.mode == ReaderMode.scroll ? _scrollView() : _singlePageView(),
        IgnorePointer(
          ignoring: _zoom <= 1.0,
          child: Opacity(
            opacity: _zoom > 1.0 ? 1 : 0,
            child: _zoomOverlay(),
          ),
        ),
      ],
    );
  }

  /// Full-screen zoom overlay shared by scroll and single-page modes. The
  /// current page is rendered at fit and scaled by a transform, so zooming
  /// never reflows the list / PageView geometry — that's what stopped the
  /// page-jump on double-tap. Pinch anchors at the focal point, one finger
  /// roams, double-tap cycles 100→150→200→100, and on settle the page
  /// re-renders once at the committed width for crisp text.
  Widget _zoomOverlay() {
    final pages = _renderPages;
    final size = MediaQuery.sizeOf(context);
    final scroll = _settings.mode == ReaderMode.scroll;
    final idx = _currentPage.clamp(0, math.max(0, pages.length - 1)).toInt();
    final page = pages[idx];
    return _ZoomablePage(
      key: ValueKey('zoom-$_anchorSeed-$idx'),
      page: page,
      pageIndex: idx,
      fitWidth: scroll ? _scrollRenderWidth : _singlePageFitWidth(page, size),
      settings: _settings,
      paper: _paperFor(_settings.atmosphere),
      pdf: _pdfRenderer,
      highlights: _highlightsByPage[idx] ?? const [],
      initialZoom: _zoom,
      anchor: _zoomAnchor,
      pinching: _pinching,
      stretchWidth: scroll,
      onZoomChanged: _setInteractiveZoom,
      onToggleChrome: _toggleChrome,
      onWordLongPress: _onWordLongPress,
    );
  }

  double _singlePageFitWidth(TextLayerPage page, Size size) {
    // Same fit as the single-page surface: keep the page below the status bar
    // / camera cutout so the zoom overlay never jumps from the surface.
    final topInset = MediaQuery.paddingOf(context).top;
    final base = math.min(
        size.width / page.width, (size.height - topInset) / page.height);
    return (page.width * base * _settings.pageZoom).clamp(80.0, 4000.0);
  }

  Widget _fixedPdfUnavailableView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Text('PDF unavailable',
            style: SereneType.uiBody
                .copyWith(color: _settings.atmosphere.text)),
      ),
    );
  }

  Widget _extractionView() {
    final progress = (_extractionProgress ?? 0).clamp(0, 100).toInt();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: null,
              strokeWidth: 6,
              color: _settings.atmosphere.accent,
              backgroundColor: _settings.atmosphere.text.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            progress > 0 ? 'Extracting text… $progress%' : 'Extracting text…',
            style: SereneType.uiBody.copyWith(color: _settings.atmosphere.text),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- page geometry

  /// Interactive session zoom from double-tap / pinch. 1.0 = fitted.
  double _zoom = 1.0;
  double _pinchStartZoom = 1.0;
  bool _pinching = false;

  /// Surface-local point the zoom overlay should zoom about (the double-tapped
  /// word / pinch focal). Only meaningful at the moment zoom is entered.
  Offset? _zoomAnchor;
  Offset? _scrollDoubleTapPos;

  static const double _minZoom = 1.0;
  static const double _maxZoom = 3.0;

  /// Double-tap zoom steps: 100% → 150% → 200% → back to 100%.
  static const List<double> _singlePageZoomSteps = [1.0, 1.5, 2.0];

  /// Converts a global position to the reading surface's local space. The
  /// scroll list, PageView and zoom overlay all fill the same area, so this is
  /// the shared coordinate space for zoom anchors.
  Offset? _toSurfaceLocal(Offset global) {
    final box = _readingKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.globalToLocal(global);
  }

  void _setInteractiveZoom(double z, {Offset? anchor}) {
    final clamped = z.clamp(_minZoom, _maxZoom);
    if ((clamped - _zoom).abs() < 0.001) return;
    final entering = _zoom <= 1.0 && clamped > 1.0;
    debugPrint('[zoom] _setInteractiveZoom $clamped entering=$entering anchor=$anchor');
    setState(() {
      _zoom = clamped;
      _zoomAnchor = anchor;
    });
  }

  void _onScrollDoubleTapDown(TapDownDetails d) {
    debugPrint('[zoom] SURFACE onScrollDoubleTapDown zoom=$_zoom');
    _scrollDoubleTapPos = _toSurfaceLocal(d.globalPosition);
  }

  void _onScrollDoubleTap() {
    debugPrint('[zoom] SURFACE onScrollDoubleTap zoom=$_zoom');
    _setInteractiveZoom(_zoom > 1.05 ? 1.0 : 1.5, anchor: _scrollDoubleTapPos);
    _scrollDoubleTapPos = null;
  }

  void _onScrollPinchStart(ScaleStartDetails d) {
    _pinching = true;
    _pinchStartZoom = _zoom;
  }

  void _onScrollPinchUpdate(ScaleUpdateDetails d) {
    _setInteractiveZoom(_pinchStartZoom * d.scale, anchor: d.focalPoint);
  }

  void _onScrollPinchEnd() {
    _pinching = false;
    setState(() {});
  }

  /// Width each rendered page gets in scroll mode: the full screen width
  /// (edge-to-edge, no boxed insets), scaled by the persisted page zoom only.
  /// Interactive zoom never reflows the list — it happens on the zoom overlay,
  /// so the scroll geometry (and the current page) stays put while zoomed.
  double get _scrollRenderWidth =>
      (MediaQuery.sizeOf(context).width * _settings.pageZoom)
          .clamp(160.0, 4000.0);

  double _pageBoxHeight(TextLayerPage p) => _scrollRenderWidth * (p.height / p.width);

  static const double _pageGap = 16;
  static const double _scrollTopPadFactor = 0.06;

  /// Top pad for the first page in scroll mode: the usual 6% breathing room,
  /// but never less than the status bar / camera-cutout inset so page text
  /// never starts hidden behind a notch or punch-hole.
  double get _scrollTopPad => math.max(
        MediaQuery.sizeOf(context).height * _scrollTopPadFactor,
        MediaQuery.paddingOf(context).top + 8,
      );

  /// Deterministic top offset of every page (no TextPainter measurement
  /// needed -- page heights come straight from the page aspect ratio).
  List<double> _scrollOffsets() {
    final out = <double>[];
    var y = _scrollTopPad;
    for (final p in _renderPages) {
      out.add(y);
      y += _pageBoxHeight(p) + _pageGap;
    }
    return out;
  }

  double _scrollOffsetForPage(int page) {
    final offsets = _scrollOffsets();
    return offsets[page.clamp(0, offsets.length - 1)];
  }

  /// The page index for a reading fraction, from the text layer's char counts
  /// when available, else a page-based approximation (run-less books).
  int _pageForFraction(double fraction) {
    final layer = _layer;
    if (layer != null && layer.totalChars > 0) {
      return layer.pageForFraction(fraction);
    }
    final count = _renderPages.length;
    if (count == 0) return 0;
    return (fraction.clamp(0.0, 0.9999) * count).floor().clamp(0, count - 1);
  }

  int? _topVisiblePageInScroll() {
    if (!_scrollController.hasClients) return null;
    final px = _scrollController.position.pixels - _scrollTopPad + 2;
    final offsets = _scrollOffsets();
    var lo = 0;
    var hi = offsets.length - 1;
    var idx = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (offsets[mid] <= px) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return idx;
  }

  // ------------------------------------------------------------------ scroll

  Widget _scrollView() {
    if (_restoreScrollOnShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollPosition());
      _restoreScrollOnShow = false;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: RawGestureDetector(
        gestures: {
          // Two-finger-only pinch so one-finger vertical scrolling is never
          // stolen by the scale recognizer (see [_TwoPointerScaleGestureRecognizer]).
          _TwoPointerScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_TwoPointerScaleGestureRecognizer>(
            _TwoPointerScaleGestureRecognizer.new,
            (r) => r
              ..onStart = _onScrollPinchStart
              ..onUpdate = _onScrollPinchUpdate
              ..onEnd = (_) => _onScrollPinchEnd(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => debugPrint('[zoom] SURFACE tapDown zoom=$_zoom'),
          onTapUp: (_) {
            debugPrint('[zoom] SURFACE onTapUp zoom=$_zoom');
            _toggleChrome();
          },
          onDoubleTapDown: _onScrollDoubleTapDown,
          onDoubleTap: _onScrollDoubleTap,
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(top: _scrollTopPad, bottom: 140),
            itemCount: _renderPages.length,
            itemBuilder: (context, i) {
              final page = _renderPages[i];
              final rw = _scrollRenderWidth;
              return Padding(
                padding: const EdgeInsets.only(bottom: _pageGap),
                child: LayoutBuilder(
                  builder: (context, cons) {
                    final viewport = cons.maxWidth;
                    // At fit the page fills the screen width edge-to-edge --
                    // continuous flow, never a boxed side-scroll. Only once it
                    // is zoomed past the screen width does the page allow
                    // horizontal panning to the rest.
                    final content = SizedBox(
                      width: rw,
                      child: TextLayerPageView(
                        page: page,
                        renderWidth: rw,
                        settings: _settings,
                        paper: _paperFor(_settings.atmosphere),
                        pdf: _pdfRenderer,
                        highlights: _highlightsByPage[i] ?? const [],
                        onWordLongPress: (global, rect, s, e, t) =>
                            _onWordLongPress(i, global, s, e, t),
                      ),
                    );
                    if (rw > viewport) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: content,
                      );
                    }
                    return Center(child: content);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _restoreScrollPosition() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final page = _pageForFraction(_progress);
    _restoreScrollToTarget(_scrollOffsetForPage(page));
  }

  void _restoreScrollToTarget(double target, {int frameBudget = 120}) {
    if (!mounted || !_scrollController.hasClients) return;
    _restoringScroll = true;
    final max = _scrollController.position.maxScrollExtent;
    final clamped = target.clamp(0.0, max);
    _scrollController.jumpTo(clamped);
    if (clamped < target && frameBudget > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _restoreScrollToTarget(target, frameBudget: frameBudget - 1);
      });
      return;
    }
    _syncPageFromScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoringScroll = false;
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.maxScrollExtent > 0) _syncPageFromScroll();
    return false;
  }

  void _syncPageFromScroll() {
    final idx = _topVisiblePageInScroll();
    if (idx == null) return;
    if (idx != _currentPage) setState(() => _currentPage = idx);
    _onPageShown(idx);
  }

  // --------------------------------------------------------------- progress

  /// Reading progress is derived from char position: the fraction of the book
  /// consumed through this page. Saved as `current_offset` so scroll, paginate,
  /// and the web reader all resume at the same spot.
  void _onPageShown(int page) {
    final layer = _layer;
    if (layer != null && layer.totalChars > 0) {
      _updateProgress(layer.fractionThrough(page));
    } else if (_renderPages.isNotEmpty) {
      _updateProgress(((page + 1) / _renderPages.length).clamp(0.0, 1.0));
    }
  }

  void _onPageChanged(int index, int total) {
    if (index != _currentPage || total != _pageCount) {
      setState(() {
        _currentPage = index;
        _pageCount = total;
      });
    }
    _onPageShown(index);
  }

  void _updateProgress(double p) {
    final clamped = p.clamp(0.0, 1.0);
    _progressNotifier.value = clamped;
    if (_restoringScroll) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      unawaited(_saveProgressNow());
    });
  }

  // -------------------------------------------------------------- single page

  PageController? _paginateController;
  int _paginateAnchor = 0;

  /// Returns the single-page view's controller, creating it once and reusing it
  /// across rebuilds. A fresh controller is only built when the mode changes
  /// (new [_anchorSeed]). Recreating it on every build made the PageView swap
  /// controllers each frame, which could dispose a page's widget while its
  /// same-index replacement mounted in the same frame.
  PageController _paginateControllerFor(int initial) {
    final current = _paginateController;
    if (current != null && _paginateAnchor == _anchorSeed) {
      return current;
    }
    final next = PageController(initialPage: initial);
    _paginateController = next;
    _paginateAnchor = _anchorSeed;
    if (current != null) {
      // The old PageView is unmounted at the end of this frame; dispose after.
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return next;
  }

  Widget _singlePageView() {
    final pages = _renderPages;
    final initial = _currentPage.clamp(0, math.max(0, pages.length - 1)).toInt();
    final controller = _paginateControllerFor(initial);
    return _SinglePageView(
      key: ValueKey('pag-$_anchorSeed'),
      controller: controller,
      pages: pages,
      settings: _settings,
      zoom: _zoom,
      onZoomChanged: _setInteractiveZoom,
      paper: _paperFor(_settings.atmosphere),
      pdf: _pdfRenderer,
      highlights: _highlightsByPage,
      initialPage: initial,
      onPageChanged: _onPageChanged,
      onWordLongPress: (page, global, s, e, t) =>
          _onWordLongPress(page, global, s, e, t),
      onToggleChrome: _toggleChrome,
      onPinchState: (v) {
        _pinching = v;
        if (!v) setState(() {});
      },
    );
  }

  // ------------------------------------------------------------- highlight

  void _onWordLongPress(int page, Offset global, int start, int end, String text) {
    HapticFeedback.selectionClick();
    final box = _readingKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(global) ??
        Offset(MediaQuery.sizeOf(context).width / 2, 120);
    setState(() {
      _highlightMenu = _HighlightMenuState(
        page: page,
        start: start,
        end: end,
        text: text,
        position: local,
      );
    });
  }

  Widget _buildHighlightMenu() {
    final menu = _highlightMenu!;
    final width = MediaQuery.sizeOf(context).width;
    final maxLeft = math.max(16.0, width - 300.0);
    final left = (menu.position.dx - 130).clamp(16.0, maxLeft);
    return Positioned(
      left: left,
      top: (menu.position.dy - 64).clamp(24.0, double.infinity),
      child: _HighlightMenu(
        colors: const ['#FCE7F3', '#FEF08A', '#BBF7D0', '#BFDBFE'],
        onColor: (hex) => _applyHighlight(hex),
        onNote: _addNote,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: menu.text));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Text copied')),
          );
          setState(() => _highlightMenu = null);
        },
        onDismiss: () => setState(() => _highlightMenu = null),
      ),
    );
  }

  void _applyHighlight(String hex) {
    final menu = _highlightMenu;
    if (menu == null) return;
    final color = _parseColor(hex, fallback: _settings.atmosphere.accent);
    setState(() {
      _highlightsByPage
          .putIfAbsent(menu.page, () => [])
          .add(PageHighlight(start: menu.start, end: menu.end, color: color));
      _highlightMenu = null;
    });
    _booksService.api.post('/sync/annotations', body: {
      'book_id': widget.book.id,
      'kind': 'highlight',
      'anchor': jsonEncode({
        'page': menu.page,
        'start_char': menu.start,
        'end_char': menu.end,
        'text': menu.text,
      }),
      'color': hex,
    });
  }

  Future<void> _addNote() async {
    final menu = _highlightMenu;
    if (menu == null) return;
    final ctl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a note'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Write something…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (note == null || note.trim().isEmpty) {
      if (mounted) setState(() => _highlightMenu = null);
      return;
    }
    if (!mounted) return;
    setState(() => _highlightMenu = null);
    _booksService.api.post('/sync/annotations', body: {
      'book_id': widget.book.id,
      'kind': 'note',
      'anchor': menu.text,
      'note_text': note.trim(),
    });
  }

  Color _parseColor(String hex, {Color fallback = const Color(0xFFFFFFFF)}) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return fallback;
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  // ----------------------------------------------------------------- chrome

  Widget _buildTopBar() {
    final text = _settings.atmosphere.text;
    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      offset: _uiVisible ? Offset.zero : const Offset(0, -1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _uiVisible ? 1 : 0,
        child: Container(
          decoration: BoxDecoration(
            color: _settings.atmosphere.background.withValues(alpha: 0.9),
            border: Border(
              bottom: BorderSide(
                color: _settings.atmosphere.text.withValues(alpha: 0.1),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: text),
                    tooltip: 'Back to library',
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SereneType.uiBody.copyWith(
                            color: text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (widget.book.author != null &&
                            widget.book.author!.isNotEmpty)
                          Text(
                            widget.book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SereneType.labelSm.copyWith(
                              color: text.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_textLayerAvailable)
                    IconButton(
                      onPressed: _toggleTextMode,
                      icon: Icon(
                        _settings.textMode
                            ? Icons.text_fields
                            : Icons.picture_as_pdf,
                        color: text,
                      ),
                      tooltip: _settings.textMode
                          ? 'Text mode: on (tap to show original PDF)'
                          : 'Text mode: off (tap to use your font)',
                    ),
                  IconButton(
                    onPressed: _reExtract,
                    icon: Icon(Icons.refresh, color: text),
                    tooltip: 'Re-extract this book',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _SyncIndicator(
                      color: _settings.atmosphere.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        offset: _uiVisible ? Offset.zero : const Offset(0, 1.2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _uiVisible ? 1 : 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _progressNotifier,
            builder: (context, value, _) => _ReaderFooter(
              progress: value,
              pageCount: _totalUnits,
              bookmarked: _bookmarked,
              background: _settings.atmosphere.background,
              text: _settings.atmosphere.text,
              accent: _settings.atmosphere.accent,
              onSeek: (v) {
                _updateProgress(v);
                _jumpToPage(_pageForFraction(v));
              },
              onGoToPage: _openGoToPage,
              onAppearance: _openAppearance,
              onSearch: _openSearch,
              onToc: _openToc,
              onToggleBookmark: _toggleBookmark,
              onAnnotations: _openAnnotations,
              annotationCount: _annotations?.length ?? 0,
              importCount:
                  (_annotations?.where((a) => a.importedFromPdf).length ?? 0),
              onTts: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Text-to-speech coming soon')),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Physical page count (both modes).
  int get _totalUnits => _renderPages.length;

  Future<void> _openAppearance() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ReaderAppearanceSheet(
          initial: _settings,
          onChanged: _updateSettings,
        ),
      ),
    );
  }

  void _openGoToPage() {
    if (!_textLayerAvailable) return;
    final current = (_currentPage + 1).clamp(1, math.max(1, _totalUnits));
    _goToPageController.text = '$current';
    setState(() => _goToPageOpen = true);
  }

  void _closeGoToPage() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_goToPageOpen) return;
    setState(() => _goToPageOpen = false);
  }

  void _submitGoToPage() {
    final page = int.tryParse(_goToPageController.text);
    _closeGoToPage();
    if (page == null || page < 1 || page > _totalUnits) return;
    // Land on the page after the current frame settles so the jump never
    // interleaves with a live element deactivation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToPage(page - 1);
    });
  }

  Widget _buildGoToPagePanel() {
    if (!_goToPageOpen) return const SizedBox.shrink();
    final atmosphere = _settings.atmosphere;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeGoToPage,
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          alignment: Alignment.center,
          // Scrollable so the panel stays readable when the keyboard leaves
          // little room (landscape): it never overflows the viewport.
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  decoration: BoxDecoration(
                    color: atmosphere.background,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Go to page',
                    style: SereneType.uiBody.copyWith(
                      color: atmosphere.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _goToPageController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submitGoToPage(),
                    decoration: InputDecoration(
                      hintText: 'Page 1 to $_totalUnits',
                      hintStyle: SereneType.labelMd.copyWith(
                        color: atmosphere.text.withValues(alpha: 0.4),
                      ),
                    ),
                    style: SereneType.uiBody.copyWith(color: atmosphere.text),
                    cursorColor: atmosphere.accent,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _closeGoToPage,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submitGoToPage,
                        child: const Text('Go'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
  }

  Future<void> _openToc() async {
    final outline = _layer?.outline ?? const <OutlineEntry>[];
    if (outline.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No table of contents')));
      return;
    }
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final chosen = await showModalBottomSheet<OutlineEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: _settings.atmosphere.background,
          borderRadius: SereneShape.sheetTop,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: SereneShape.fullPill,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text('Table of Contents',
                    style: SereneType.title.copyWith(
                        color: _settings.atmosphere.text)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: outline.length,
                  itemBuilder: (context, i) {
                    final e = outline[i];
                    final active = _currentPage == e.page;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(
                        left: 16 + (e.level.clamp(1, 4) - 1) * 16.0,
                        right: 16,
                      ),
                      title: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SereneType.uiBody.copyWith(
                          color: active
                              ? _settings.atmosphere.accent
                              : _settings.atmosphere.text,
                          fontWeight: e.level <= 1 ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      trailing: Text(
                        '${e.page + 1}',
                        style: SereneType.labelSm.copyWith(
                          color: _settings.atmosphere.text.withValues(alpha: 0.5),
                        ),
                      ),
                      onTap: () => Navigator.pop(context, e),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _jumpToPage(chosen.page);
  }

  Future<void> _openSearch() async {
    if (!_textLayerAvailable) return;
    final ctl = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search in this book'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type to search…'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (query == null || query.trim().isEmpty) return;

    final q = query.trim().toLowerCase();
    final matches = <(int, String)>[];
    for (var p = 0; p < _layer!.pages.length; p++) {
      final text = _layer!.pages[p].text;
      if (text.toLowerCase().contains(q)) matches.add((p, text));
    }
    if (matches.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No matches')));
      return;
    }
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final chosen = await showDialog<(int, String)>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  '${matches.length} result${matches.length == 1 ? '' : 's'}',
                  style: SereneType.labelMd
                      .copyWith(color: _settings.atmosphere.text),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: math.min(matches.length, 8),
                  itemBuilder: (context, i) {
                    final m = matches[i];
                    final idx = m.$2.toLowerCase().indexOf(q);
                    final start = math.max(0, idx - 30);
                    final end = math.min(m.$2.length, idx + q.length + 50);
                    final snippet = m.$2.substring(start, end)
                        .replaceAll('\n', ' ');
                    return ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                      title: Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SereneType.uiBody
                            .copyWith(color: _settings.atmosphere.text),
                      ),
                      subtitle: Text(
                        'Page ${m.$1 + 1}',
                        style: SereneType.labelSm.copyWith(
                          color: _settings.atmosphere.text.withValues(alpha: 0.6),
                        ),
                      ),
                      onTap: () => Navigator.pop(context, m),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _jumpToPage(chosen.$1);
  }
}

class _HighlightMenuState {
  final int page;
  final int start;
  final int end;
  final String text;
  final Offset position;
  const _HighlightMenuState({
    required this.page,
    required this.start,
    required this.end,
    required this.text,
    required this.position,
  });
}

class _HighlightMenu extends StatelessWidget {
  final List<String> colors;
  final ValueChanged<String> onColor;
  final VoidCallback onNote;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;
  const _HighlightMenu({
    required this.colors,
    required this.onColor,
    required this.onNote,
    required this.onCopy,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onDismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2F3130),
            borderRadius: BorderRadius.all(SereneShape.md),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in colors) ...[
                GestureDetector(
                  onTap: () => onColor(c),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(width: 1, height: 24, color: const Color(0x3DFFFFFF)),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onNote,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_comment, size: 20, color: Colors.white),
              ),
              IconButton(
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.content_copy, size: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A [ScaleGestureRecognizer] that only claims the gesture once a second
/// pointer is down. This lets single-finger swipes (page flips, vertical
/// scroll) win the arena, while a genuine two-finger pinch still zooms.
///
/// Every pointer is registered with [super.addAllowedPointer] so the recognizer
/// tracks both fingers and can compute a real span (without this, scale is
/// always 1.0 and a pinch is misread as a pan). Single-finger movement is
/// dropped in [handleEvent] so the recognizer never advances its state machine
/// on one finger and thus never steals scroll / page flips.
class _TwoPointerScaleGestureRecognizer extends ScaleGestureRecognizer {
  int _pointersDown = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointersDown++;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointersDown--;
    }
    // Single-finger moves are dropped so the recognizer never accumulates
    // enough focal movement to claim the gesture; once the second finger is
    // down every event is forwarded and span/scale are computed from both.
    if (event is PointerMoveEvent && _pointersDown < 2) return;
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointersDown = 0;
    super.didStopTrackingLastPointer(pointer);
  }
}

/// The single-page reading surface: one full PDF page fitted to the screen at
/// a time, turned with a left/right swipe (tap zones flip too). Double-tap
/// cycles zoom 100% → 150% → 200% → 100%, pinch zooms continuously, and once
/// zoomed past the viewport the page pans both axes (Adobe-style). At fit the
/// whole page is always visible — the top is never clipped.
class _SinglePageView extends StatefulWidget {
  final PageController controller;
  final List<TextLayerPage> pages;
  final ReaderSettings settings;
  final double zoom;
  final void Function(double zoom, {Offset? anchor}) onZoomChanged;
  final Color paper;
  final PdfRenderer pdf;
  final Map<int, List<PageHighlight>> highlights;
  final int initialPage;
  final void Function(int index, int total) onPageChanged;
  final void Function(int page, Offset global, int start, int end, String text)
      onWordLongPress;
  final VoidCallback onToggleChrome;
  final ValueChanged<bool>? onPinchState;

  const _SinglePageView({
    super.key,
    required this.controller,
    required this.pages,
    required this.settings,
    required this.zoom,
    required this.onZoomChanged,
    required this.paper,
    required this.pdf,
    required this.highlights,
    required this.initialPage,
    required this.onPageChanged,
    required this.onWordLongPress,
    required this.onToggleChrome,
    this.onPinchState,
  });

  @override
  State<_SinglePageView> createState() => _SinglePageViewState();
}

class _SinglePageViewState extends State<_SinglePageView> {
  double _pinchStartZoom = 1.0;
  Offset? _doubleTapPos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onPageChanged(widget.initialPage, widget.pages.length);
      }
    });
  }

  void _flip(int delta) {
    final target = _current + delta;
    if (target < 0 || target >= widget.pages.length) return;
    widget.controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int get _current => widget.controller.hasClients
      ? widget.controller.page?.round() ?? widget.initialPage
      : widget.initialPage;

  void _onTapUp(TapUpDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final x = d.globalPosition.dx;
    if (x < w * 0.3) {
      _flip(-1);
    } else if (x > w * 0.7) {
      _flip(1);
    } else {
      widget.onToggleChrome();
    }
  }

  Offset? _toSurfaceLocal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _onDoubleTapDown(TapDownDetails d) =>
      _doubleTapPos = _toSurfaceLocal(d.globalPosition);

  void _onDoubleTap() {
    const steps = _ReaderScreenState._singlePageZoomSteps;
    final idx = steps.indexOf(widget.zoom);
    widget.onZoomChanged(
      idx == -1 ? 1.5 : steps[(idx + 1) % steps.length],
      anchor: _doubleTapPos,
    );
    _doubleTapPos = null;
  }

  void _onPinchStart(ScaleStartDetails d) {
    widget.onPinchState?.call(true);
    _pinchStartZoom = widget.zoom;
  }

  void _onPinchUpdate(ScaleUpdateDetails d) {
    widget.onZoomChanged(
      _pinchStartZoom * d.scale,
      anchor: d.focalPoint,
    );
  }

  void _onPinchEnd() => widget.onPinchState?.call(false);

  Widget _buildPage(TextLayerPage page, double renderWidth, int physicalIdx) {
    return TextLayerPageView(
      page: page,
      renderWidth: renderWidth,
      settings: widget.settings,
      paper: widget.paper,
      pdf: widget.pdf,
      highlights: widget.highlights[physicalIdx] ?? const [],
      onWordLongPress: (global, rect, s, e, t) =>
          widget.onWordLongPress(physicalIdx, global, s, e, t),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: widget.controller,
      onPageChanged: (i) => widget.onPageChanged(i, widget.pages.length),
      itemCount: widget.pages.length,
      itemBuilder: (context, i) {
        final size = MediaQuery.sizeOf(context);
        final page = widget.pages[i];
        // Fit the whole page inside the safe area (both axes) so nothing is
        // clipped and page text never starts behind the status bar / camera
        // cutout. Interactive zoom lives on the zoom overlay, never here, so
        // the PageView geometry (and the current page) stays put while zoomed.
        final topInset = MediaQuery.paddingOf(context).top;
        final availW = size.width;
        final availH = size.height - topInset;
        final base = math.min(availW / page.width, availH / page.height);
        final rw = (page.width * base * widget.settings.pageZoom)
            .clamp(80.0, 4000.0);
        final pageH = rw * page.height / page.width;
        final topPad = topInset + (availH - pageH) / 2;
        final child = _buildPage(page, rw, i);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          child: RawGestureDetector(
            gestures: {
              // Two-finger-only pinch so a one-finger swipe still flips pages.
              _TwoPointerScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<_TwoPointerScaleGestureRecognizer>(
                _TwoPointerScaleGestureRecognizer.new,
                (r) => r
                  ..onStart = _onPinchStart
                  ..onUpdate = _onPinchUpdate
                  ..onEnd = (_) => _onPinchEnd(),
              ),
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: topPad),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen Adobe-style zoom surface shared by scroll and single-page
/// modes. The current page is rendered at its fitted width and scaled by a
/// pure matrix transform, so zooming never re-lays-out the document. Pinch
/// anchors at the focal point, a single finger roams the page, and double-tap
/// cycles 100% → 150% → 200% → back to 100%. On each gesture settle the scale
/// is committed: the page re-renders once at the new width for crisp text.
class _ZoomablePage extends StatefulWidget {
  final TextLayerPage page;
  final int pageIndex;
  final double fitWidth;
  final ReaderSettings settings;
  final Color paper;
  final PdfRenderer? pdf;
  final List<PageHighlight> highlights;
  final double initialZoom;
  final Offset? anchor;
  final bool pinching;
  final bool stretchWidth;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onToggleChrome;
  final void Function(int page, Offset global, int start, int end, String text)
      onWordLongPress;

  const _ZoomablePage({
    super.key,
    required this.page,
    required this.pageIndex,
    required this.fitWidth,
    required this.settings,
    required this.paper,
    required this.pdf,
    required this.highlights,
    required this.initialZoom,
    required this.stretchWidth,
    required this.onZoomChanged,
    required this.onToggleChrome,
    required this.onWordLongPress,
    this.anchor,
    this.pinching = false,
  });

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  static const double _maxZoom = 3.0;

  /// Settled scale baked into the page's render width.
  double _committed = 1.0;

  /// Live extra scale applied by the transform during a gesture.
  double _gesture = 1.0;

  /// The page's top-left offset on screen (surface-local pixels).
  Offset _translation = Offset.zero;

  double _pinchBase = 1.0;
  Offset _doubleTapPos = Offset.zero;

  double get _visualScale => _committed * _gesture;

  Size get _viewport => MediaQuery.sizeOf(context);

  /// Where the page's top-left sits on screen at 100%.
  Offset get _fitTopLeft {
    if (widget.stretchWidth) return Offset.zero;
    final h = widget.page.height * (widget.fitWidth / widget.page.width);
    // Match the single-page surface placement: centered within the safe area
    // below the status bar / camera cutout, never under it.
    final topInset = MediaQuery.paddingOf(context).top;
    final availH = _viewport.height - topInset;
    return Offset(
      (_viewport.width - widget.fitWidth) / 2,
      topInset + (availH - h) / 2,
    );
  }

  @override
  void initState() {
    super.initState();
    final s = widget.initialZoom.clamp(1.0, _maxZoom);
    _committed = s;
    debugPrint('[zoom] overlay mount key=${widget.key} page=${widget.pageIndex} scale=$s '
        'anchor=${widget.anchor} stretch=${widget.stretchWidth}');
    if (s > 1.0) {
      final p0 = _fitTopLeft;
      final anchor = widget.anchor ?? _viewport.center(Offset.zero);
      _translation = _clampTranslation(p0 + (anchor - p0) * (1 - s));
    }
  }

  @override
  void didUpdateWidget(_ZoomablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final s = widget.initialZoom.clamp(1.0, _maxZoom);
    final wasZoomed = oldWidget.initialZoom > 1.0;
    final isZoomed = s > 1.0;

    if (widget.pinching) {
      // Surface pinch in progress: mirror the live scale as a pure transform
      // (no page re-render) while keeping the focal anchor fixed.
      if (isZoomed) {
        final old = _visualScale;
        if (old > 0) {
          final k = s / old;
          final anchor = widget.anchor;
          if (anchor != null) _translation = anchor + (_translation - anchor) * k;
          _gesture = _committed > 0 ? s / _committed : 1.0;
          _translation = _clampTranslation(_translation);
        }
      } else {
        // Pinched back below 100%: hold at the fitted size.
        _gesture = _committed > 0 ? 1.0 / _committed : 1.0;
      }
    } else if (!wasZoomed && isZoomed) {
      // Zoom entered: anchor the page about the double-tapped / pinched point.
      _committed = s;
      _gesture = 1.0;
      final p0 = _fitTopLeft;
      final anchor = widget.anchor ?? _viewport.center(Offset.zero);
      _translation = _clampTranslation(p0 + (anchor - p0) * (1 - s));
      debugPrint('[zoom] didUpdate enter s=$s p0=$p0 anchor=$anchor '
          't=${_translation} viewport=$_viewport fit=${widget.fitWidth}');
    } else if (wasZoomed && !isZoomed) {
      _committed = 1.0;
      _gesture = 1.0;
      _translation = Offset.zero;
    } else if (isZoomed && (_gesture != 1.0 || (s - _committed).abs() > 0.001)) {
      // Gesture settle / zoom change: commit once for a crisp re-render.
      _committed = s;
      _gesture = 1.0;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    debugPrint('[zoom] overlay dispose');
    super.dispose();
  }

  Offset _clampTranslation(Offset t) {
    final v = _viewport;
    final w = widget.fitWidth * _visualScale;
    final h =
        widget.page.height * (widget.fitWidth / widget.page.width) * _visualScale;
    final x = w <= v.width ? (v.width - w) / 2 : t.dx.clamp(v.width - w, 0.0);
    final y = h <= v.height ? (v.height - h) / 2 : t.dy.clamp(v.height - h, 0.0);
    debugPrint('[zoom] clamp in=$t -> ($x,$y) viewport=$v w=$w h=$h');
    return Offset(x, y);
  }

  void _onPinchStart(ScaleStartDetails d) => _pinchBase = _visualScale;

  void _onPinchUpdate(ScaleUpdateDetails d) {
    final old = _visualScale;
    if (old <= 0) return;
    final newScale = (_pinchBase * d.scale).clamp(1.0, _maxZoom);
    final k = newScale / old;
    final f = d.focalPoint;
    // Keep the point under the fingers fixed: t' = f + (t - f) * k.
    _translation = f + (_translation - f) * k;
    _gesture = _committed > 0 ? newScale / _committed : 1.0;
    _translation = _clampTranslation(_translation);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _translation = _clampTranslation(_translation + d.delta);
    setState(() {});
  }

  void _onDoubleTapDown(TapDownDetails d) {
    debugPrint('[zoom] OVERLAY onDoubleTapDown committed=$_committed');
    _doubleTapPos = d.localPosition;
  }

  void _onDoubleTap() {
    final s = _visualScale;
    final f = _doubleTapPos;
    final double target;
    if (s < 1.25) {
      target = 1.5;
    } else if (s < 1.75) {
      target = 2.0;
    } else {
      widget.onZoomChanged(1.0);
      return;
    }
    // Zoom about the tapped point, then commit for a crisp re-render.
    final k = target / s;
    _translation = _clampTranslation(f + (_translation - f) * k);
    _committed = target;
    _gesture = 1.0;
    debugPrint('[zoom] doubleTap from=$s to=$target at=$f t=${_translation}');
    widget.onZoomChanged(target);
    setState(() {});
  }

  /// Called when a pinch or pan ends: bake the live scale into the committed
  /// width (one crisp re-render) and sync the reader's zoom state.
  void _onInteractionEnd() {
    final s = _visualScale.clamp(1.0, _maxZoom);
    _committed = s;
    _gesture = 1.0;
    _translation = _clampTranslation(_translation);
    debugPrint('[zoom] interactionEnd scale=$s t=${_translation}');
    if (mounted) setState(() {});
    widget.onZoomChanged(s);
  }

  @override
  Widget build(BuildContext context) {
    // While not zoomed the overlay still exists (so its element and render
    // object stay stable for hit-testing) but renders nothing, so scrolling /
    // page turns never pay for an invisible re-render of the current page.
    if (_committed <= 1.0 && _gesture <= 1.0) return const SizedBox.shrink();
    final rw = (widget.fitWidth * _committed).clamp(80.0, 4000.0);    final rh = widget.page.height * (rw / widget.page.width);
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, _gesture)
      ..setEntry(1, 1, _gesture)
      ..setTranslationRaw(_translation.dx, _translation.dy, 0);

    final content = SizedBox(
      width: rw,
      height: rh,
      child: TextLayerPageView(
        page: widget.page,
        renderWidth: rw,
        settings: widget.settings,
        paper: widget.paper,
        pdf: widget.pdf,
        highlights: widget.highlights,
        onWordLongPress: (global, rect, s, e, t) =>
            widget.onWordLongPress(widget.pageIndex, global, s, e, t),
      ),
    );

    return ClipRect(
      child: Container(
        color: widget.paper,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => debugPrint('[zoom] OVERLAY tapDown'),
          onTapUp: (_) {
            debugPrint('[zoom] OVERLAY onTapUp');
            widget.onToggleChrome();
          },
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onInteractionEnd(),
          child: RawGestureDetector(
            gestures: {
              _TwoPointerScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<_TwoPointerScaleGestureRecognizer>(
                _TwoPointerScaleGestureRecognizer.new,
                (r) => r
                  ..onStart = _onPinchStart
                  ..onUpdate = _onPinchUpdate
                  ..onEnd = (_) => _onInteractionEnd(),
              ),
            },
            child: Transform(
              transform: matrix,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// The reader's bottom chrome: a scrubbable progress slider with percent/pages
/// labels and a row of action buttons (annotations, TOC, appearance, search,
/// bookmark, TTS).
class _ReaderFooter extends StatelessWidget {
  final double progress;
  final int pageCount;
  final bool bookmarked;
  final Color background;
  final Color text;
  final Color accent;
  final ValueChanged<double> onSeek;
  final VoidCallback onGoToPage;
  final VoidCallback onAppearance;
  final VoidCallback onSearch;
  final VoidCallback onToc;
  final VoidCallback onToggleBookmark;
  final VoidCallback onTts;
  final VoidCallback onAnnotations;
  final int annotationCount;
  final int importCount;
  const _ReaderFooter({
    required this.progress,
    required this.pageCount,
    required this.bookmarked,
    required this.background,
    required this.text,
    required this.accent,
    required this.onSeek,
    required this.onGoToPage,
    required this.onAppearance,
    required this.onSearch,
    required this.onToc,
    required this.onToggleBookmark,
    required this.onTts,
    required this.onAnnotations,
    this.annotationCount = 0,
    this.importCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final muted = text.withValues(alpha: 0.7);
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final pages = pageCount > 0 ? '$pageCount p.' : '— p.';
    return Container(
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: text.withValues(alpha: 0.1)),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.right,
                    style: SereneType.labelSm.copyWith(color: muted),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SeekBar(
                    fraction: progress,
                    fill: accent,
                    track: text.withValues(alpha: 0.22),
                    onSeek: onSeek,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  child: TextButton(
                    onPressed: onGoToPage,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      pages,
                      textAlign: TextAlign.left,
                      style: SereneType.labelSm.copyWith(
                        color: muted,
                        decoration: TextDecoration.underline,
                        decorationColor: muted.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _FooterAction(
                  icon: Icons.format_quote,
                  color: text,
                  onTap: onAnnotations,
                  tooltip: 'Highlights & Notes',
                  badge: importCount > 0 ? '$importCount' : null,
                ),
                _FooterAction(
                  icon: Icons.toc,
                  color: text,
                  onTap: onToc,
                  tooltip: 'Table of Contents',
                ),
                _FooterAction(
                  icon: Icons.font_download,
                  color: text,
                  onTap: onAppearance,
                  tooltip: 'Appearance',
                ),
                _FooterAction(
                  icon: Icons.search,
                  color: text,
                  onTap: onSearch,
                  tooltip: 'Search in this book',
                ),
                _FooterAction(
                  icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: bookmarked ? accent : text,
                  onTap: onToggleBookmark,
                  tooltip: 'Bookmark this page',
                ),
                _FooterAction(
                  icon: Icons.volume_up,
                  color: text,
                  onTap: onTts,
                  tooltip: 'Text to speech',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps an atmosphere to the paper color of its book pages, close to the web
/// reader's `paperFor` palette.
Color _paperFor(ReadingAtmosphere a) => switch (a.id) {
      AtmosphereId.light => const Color(0xFFFFFDFB),
      AtmosphereId.dark => const Color(0xFF26262B),
      AtmosphereId.sepia => const Color(0xFFFBF5E9),
      AtmosphereId.night => const Color(0xFF1E293B),
      AtmosphereId.paper => const Color(0xFFF8F0DC),
      AtmosphereId.modern => const Color(0xFFFFFFFF),
      AtmosphereId.mint => const Color(0xFFF8FBF6),
      AtmosphereId.rose => const Color(0xFFFDF4F5),
      AtmosphereId.ocean => const Color(0xFFF3F7FB),
      AtmosphereId.forest => const Color(0xFFF3F8F1),
    };

/// A sync status indicator in the reader header: a small cloud icon with a
/// gently breathing dot, matching the AnyShelf design.
class _SyncIndicator extends StatefulWidget {
  final Color color;
  const _SyncIndicator({required this.color});

  @override
  State<_SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<_SyncIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_done, size: 16, color: widget.color),
        const SizedBox(width: 6),
        ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.15).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

/// A large tappable action button used in the reader footer.
class _FooterAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  final String? badge;
  const _FooterAction({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, size: 28, color: color);
    return IconButton(
      onPressed: onTap,
      icon: badge != null
          ? Badge(
              label: Text(badge!, style: const TextStyle(fontSize: 10)),
              backgroundColor: color.withValues(alpha: 0.25),
              child: child,
            )
          : child,
      tooltip: tooltip,
      padding: const EdgeInsets.all(10),
    );
  }
}

/// A horizontal reading-progress slider you can tap or drag to scrub through
/// the book: a filled accent track with a small thumb, web-app style.
class _SeekBar extends StatelessWidget {
  final double fraction;
  final Color fill;
  final Color track;
  final ValueChanged<double> onSeek;
  const _SeekBar({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;
        double fractionFromDx(double dx) =>
            barWidth <= 0 ? 0 : (dx / barWidth).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) => onSeek(fractionFromDx(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) =>
              onSeek(fractionFromDx(d.localPosition.dx)),
          child: SizedBox(
            height: 28,
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: track,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: barWidth <= 0
                        ? 0.0
                        : (f * barWidth - 9.0)
                            .clamp(0.0, math.max(0.0, barWidth - 18.0))
                            .toDouble(),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: fill,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The "Highlights & Notes" sheet shown from the reader footer.
class _AnnotationsSheet extends StatelessWidget {
  final List<Annotation> annotations;
  final ReadingAtmosphere atmosphere;
  final bool canTap;
  final ValueChanged<String> onTapHighlight;

  const _AnnotationsSheet({
    required this.annotations,
    required this.atmosphere,
    required this.canTap,
    required this.onTapHighlight,
  });

  static Color _parseColor(String? hex, Color fallback) {
    if (hex == null) return fallback;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return fallback;
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  @override
  Widget build(BuildContext context) {
    final bg = atmosphere.background;
    final text = atmosphere.text;
    final muted = text.withValues(alpha: 0.7);
    final hint = text.withValues(alpha: 0.45);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: SereneShape.sheetTop,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: text.withValues(alpha: 0.2),
                    borderRadius: SereneShape.fullPill,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Text('Highlights & Notes',
                    style: SereneType.title.copyWith(color: text)),
              ),
              if (annotations.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  child: Text(
                    'No highlights or notes yet. Long-press a word to highlight '
                    'a passage, or open this book in a PDF reader to import its '
                    'annotations.',
                    style: SereneType.uiBody.copyWith(color: muted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: annotations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _AnnotationTile(
                      annotation: annotations[i],
                      text: text,
                      muted: muted,
                      hint: hint,
                      accent: atmosphere.accent,
                      canTap: canTap,
                      onTap: annotations[i].kind == 'highlight'
                          ? () {
                              final t = annotations[i].anchoredText;
                              if (t != null && t.isNotEmpty) {
                                Navigator.of(context).pop();
                                onTapHighlight(t);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single annotation in the Highlights & Notes sheet.
class _AnnotationTile extends StatelessWidget {
  final Annotation annotation;
  final Color text;
  final Color muted;
  final Color hint;
  final Color accent;
  final bool canTap;
  final VoidCallback? onTap;

  const _AnnotationTile({
    required this.annotation,
    required this.text,
    required this.muted,
    required this.hint,
    required this.accent,
    required this.canTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kind = annotation.kind;
    final isHighlight = kind == 'highlight';
    final color = _AnnotationsSheet._parseColor(annotation.color, accent);
    final body = isHighlight
        ? (annotation.anchoredText ?? '')
        : (annotation.noteText ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.all(SereneShape.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: text.withValues(alpha: 0.04),
            borderRadius: BorderRadius.all(SereneShape.md),
            border: Border.all(color: text.withValues(alpha: 0.08)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  isHighlight ? Icons.format_quote : Icons.sticky_note_2_outlined,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (body.trim().isNotEmpty)
                      Text(
                        body.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: SereneType.readingBody.copyWith(
                          color: text,
                          fontSize: 15,
                          height: 20 / 15,
                        ),
                      )
                    else
                      Text(
                        annotation.importedFromPdf
                            ? 'Imported PDF note (no matched text)'
                            : 'Empty ${isHighlight ? 'highlight' : 'note'}',
                        style: SereneType.uiBody.copyWith(
                          color: hint,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (annotation.importedFromPdf)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _AnnotationsSheet._parseColor(
                              '#8BC34A',
                              accent,
                            ).withValues(alpha: 0.18),
                            borderRadius: SereneShape.fullPill,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.import_export,
                                  size: 12,
                                  color: _AnnotationsSheet._parseColor(
                                      '#8BC34A', accent)),
                              const SizedBox(width: 4),
                              Text(
                                'Imported from PDF',
                                style: SereneType.labelSm.copyWith(
                                  color: text.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (canTap && isHighlight)
                Icon(Icons.chevron_right, size: 18, color: hint),
            ],
          ),
        ),
      ),
    );
  }
}
