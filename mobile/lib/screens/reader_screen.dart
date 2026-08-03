import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'
    hide Annotation;

import '../models/book.dart';
import '../models/annotation.dart';
import '../models/reader_settings.dart';
import '../services/books_service.dart';
import '../services/settings_service.dart';
import '../theme/reader_atmosphere.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import 'reader_appearance_sheet.dart';

/// The immersive reader. Renders reflowed text (scroll or paginated) with the
/// chosen atmosphere, or falls back to the fixed PDF when a book isn't
/// reflowable. Tapping the page toggles the chrome; long-pressing a paragraph
/// opens the floating highlight menu.
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
  final _BookController _bookController = _BookController();

  late ReaderSettings _settings = ReaderSettings.defaults();
  StructuredText? _structured;
  String? _pdfUrl; // resolved from GET /books/{id} (list omits pdf_url)
  double? _reflowConfidence; // from GET /books/{id}; may lag the list snapshot
  bool _uiVisible = false;
  bool _bookmarked = false;
  String? _bookmarkId; // backend annotation id of the current bookmark, if any
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;

  // Text-extraction status: while a freshly uploaded book is still being
  // processed the structured text isn't ready, so we show a looping extraction
  // animation and poll until the backend reports "done".
  String? _extractionStatus;
  double? _extractionProgress;
  Timer? _extractionTimer;

  // cached, time-sliced pagination state
  List<List<(TextBlock, int)>>? _pages;
  String? _pagesKey;
  Timer? _paginateTimer;
  bool _paginating = false;

  // highlight state
  Map<int, String> _highlights = {}; // global block index -> color hex
  _HighlightMenuState? _highlightMenu;

  // Set when the scroll list should re-position itself to the current reading
  // progress next time it builds (e.g. switching paginated -> scroll).
  bool _restoreScrollOnShow = false;

  // The exact block the reader is anchored on when switching modes. Captured
  // at the moment of the switch so scroll & paginated views can both resolve to
  // the same content instead of a fuzzy progress fraction that drifts a chapter.
  int? _anchorBlock;

  // Annotations loaded from the backend, cached for the panel. Populated
  // lazily so the banner badge and the Highlights & Notes sheet can render
  // without a second network call.
  List<Annotation>? _annotations;

  // page tracking for the footer (paginated mode)
  int _currentPage = 0;
  int _pageCount = 0;

  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

  double get _progress => _progressNotifier.value;

  // Reflow (and thus pagination) is available when the structured text loaded
  // and the book's reflow confidence is high enough. Prefer the fresh value
  // from GET /books/{id}: the list snapshot can be stale (extraction was still
  // running when the card was fetched, so its confidence was null).
  bool get _reflowAvailable =>
      (_reflowConfidence ?? widget.book.reflowConfidence ?? 0) >= 0.5 &&
      _structured != null;

  /// True while the book's text is still being extracted and structured data
  /// isn't ready yet. Drives the looping extraction animation.
  bool get _isExtracting =>
      _structured == null &&
      _extractionStatus != 'done' &&
      _extractionStatus != 'failed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _paginateTimer?.cancel();
    _extractionTimer?.cancel();
    _scrollController.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await _booksService.get(widget.book.id);
      final (settings, bookmark, progress, structured) = await (
        _settingsService.fetch(),
        _loadBookmark(),
        _booksService.progress(widget.book.id).onError((_, __) => 0.0),
        detail.structuredTextUrl != null
            ? _booksService.structuredText(detail)
            : Future<StructuredText?>.value(null),
      ).wait;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _structured = structured;
        _reflowConfidence = detail.reflowConfidence;
        _extractionStatus = detail.extractionStatus;
        _pdfUrl = detail.pdfUrl;
        _progressNotifier.value = progress;
        _bookmarked = bookmark != null;
        _bookmarkId = bookmark;
        _loading = false;
      });
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

  /// Starts a background poll for a book whose structured text isn't ready
  /// yet (extraction still running on the backend). The looping extraction
  /// animation shows until the poll reports "done", then we reload to pull
  /// the now-available structured text.
  void _maybeExtractPoll() {
    if (_structured != null) return;
    if (_extractionStatus == 'done' || _extractionStatus == 'failed') return;
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
      // Capture which block is current *before* switching, so the new view can
      // land on the same content (not a fuzzy fraction that drifts a chapter).
      _anchorBlock = _captureAnchorBlock();
    }
    setState(() {
      _settings = next;
      if (next.mode == ReaderMode.scroll) _restoreScrollOnShow = true;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _settingsService.save(next);
    });
  }

  /// Finds the synced bookmark annotation id for this book, if one exists.
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
        'anchor': '',
      });
      if (res is Map && res['id'] != null) {
        setState(() => _bookmarkId = res['id'] as String);
      }
    } catch (_) {
      setState(() => _bookmarked = false);
    }
  }

  /// Reconcile saved annotations (user highlights + imported PDF highlights)
  /// against the reflowed blocks so they render in both scroll and paginated
  /// modes without requiring the user to re-select them.
  Future<void> _applySavedHighlights() async {
    final anns = await _loadAnnotations();
    if (anns.isEmpty) return;
    final blocks = _structured?.allBlocks;
    if (blocks == null || blocks.isEmpty) return;
    final merged = Map<int, String>.from(_highlights);
    for (final a in anns) {
      if (a.kind != 'highlight') continue;
      final text = a.anchoredText;
      if (text == null || text.isEmpty) continue;
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].text.contains(text)) {
          merged[i] = a.color ?? (a.importedFromPdf ? '#8BC34A' : '#FFD54F');
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() => _highlights = merged);
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
    final blocks = _structured?.allBlocks ?? [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnotationsSheet(
        annotations: anns,
        blocks: blocks,
        atmosphere: _settings.atmosphere,
        onTapHighlight: (String text) => _scrollToAnnotatedText(text, blocks),
      ),
    );
  }

  void _scrollToAnnotatedText(String text, List<TextBlock> blocks) {
    if (blocks.isEmpty) return;
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].text.contains(text)) {
        final progress = blocks.length > 1 ? i / (blocks.length - 1) : 0.0;
        _updateProgress(progress);
        _scrollToProgress(progress);
        return;
      }
    }
  }

  double get _fontSize => _settings.fontSize;
  double get _lineSpacing => _settings.lineHeight.value;
  double get _readingInset => _clampReadingInset(MediaQuery.sizeOf(context).width);

  double _clampReadingInset(double width) {
    final factor = switch (_settings.margins) {
      MarginLevel.small => 0.06,
      MarginLevel.medium => 0.09,
      MarginLevel.large => 0.12,
    };
    return (width * factor).clamp(24.0, 96.0);
  }

  TextStyle get _bodyStyle => GoogleFonts.getFont(
        _settings.fontFamily,
        textStyle: TextStyle(
          fontSize: _fontSize,
          height: _lineSpacing,
          color: _settings.atmosphere.text,
        ),
      );

  TextStyle get _headingStyle => _bodyStyle.copyWith(
        fontSize: _fontSize * 1.3,
        fontWeight: FontWeight.w700,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _settings.atmosphere.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _settings.atmosphere.background,
        body: Center(
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
        ),
      );
    }

    return Scaffold(
      backgroundColor: _settings.atmosphere.background,
      body: Stack(
        key: _readingKey,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: (_) => _tapDownPos = null,
              child: _readingSurface(),
            ),
          ),
          if (_highlightMenu != null) _buildHighlightMenu(),
          _buildTopBar(),
          _buildBottomBar(),
        ],
      ),
    );
  }

  // Raw pointer tap detection. The reading surface (especially the PDF viewer)
  // claims normal tap gestures internally, so a GestureDetector on top would
  // never see taps. A Listener sees every pointer event regardless, letting us
  // toggle the chrome with a quick tap while still scrolling/pinching the book.
  Offset? _tapDownPos;
  DateTime _tapDownAt = DateTime.now();

  void _onPointerDown(PointerDownEvent e) {
    _tapDownPos = e.position;
    _tapDownAt = DateTime.now();
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _tapDownPos;
    if (down == null) return;
    _tapDownPos = null;
    final moved = (e.position - down).distance > 14;
    final quick = DateTime.now().difference(_tapDownAt) <
        const Duration(milliseconds: 400);
    // In paginated reflow mode the page view owns taps (tap zones flip pages,
    // the centre toggles chrome); everywhere else a quick tap toggles chrome.
    if (_reflowAvailable && _settings.mode == ReaderMode.paginated) return;
    if (!moved && quick) _toggleChrome();
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
    if (!_reflowAvailable) return _fixedPdfView();
    return _settings.mode == ReaderMode.scroll
        ? _scrollView()
        : _paginatedView();
  }

  /// Looping circular extraction animation shown while the backend is still
  /// processing the book's text. Renders the reader the moment it completes.
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
              value: null, // indeterminate -- spins until extraction completes
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

  Widget _fixedPdfView() {
    final url = _pdfUrl;
    return Container(
      color: Colors.black,
      child: url == null || url.isEmpty
          ? Center(
              child: Text('PDF unavailable',
                  style: SereneType.uiBody
                      .copyWith(color: _settings.atmosphere.text)),
            )
          : SfPdfViewerTheme(
              data: SfPdfViewerThemeData(
                backgroundColor: Colors.black,
                progressBarColor: _settings.atmosphere.accent,
              ),
              child: SfPdfViewer.network(
                url,
                pageSpacing: 0,
                canShowScrollHead: false,
                canShowPaginationDialog: false,
                enableDoubleTapZooming: true,
              ),
            ),
    );
  }

  Widget _scrollView() {
    final blocks = _structured!.allBlocks;
    if (_restoreScrollOnShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScrollPosition());
      _restoreScrollOnShow = false;
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          _readingInset,
          MediaQuery.sizeOf(context).height * 0.1,
          _readingInset,
          140,
        ),
        itemCount: blocks.length,
        itemBuilder: (context, index) => _buildBlock(blocks[index], index),
      ),
    );
  }

  /// Jump the scroll list to the exact block the reader was on (captured when
  /// leaving paginated mode), so switching views keeps the same content rather
  /// than drifting back a chapter. Falls back to a progress fraction when no
  /// block anchor exists (e.g. opening fresh in scroll mode).
  void _restoreScrollPosition() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final target = _scrollOffsetForBlock(_anchorBlock) ?? (_progress * max);
    _scrollController.jumpTo(target.clamp(0.0, max));
    _anchorBlock = null;
  }

  /// Build a table of the top offset of every reflowed block, measured the
  /// same way the paginator measures them (TextPainter + the same bottom
  /// padding as [_buildBlock]), so a block index maps deterministically to a
  /// scroll pixel.
  List<double> _blockOffsets(List<TextBlock> blocks, double width) {
    final offsets = <double>[];
    var y = 0.0;
    for (final b in blocks) {
      offsets.add(y);
      final style = b.isHeading ? _headingStyle : _bodyStyle;
      final tp = TextPainter(
        text: TextSpan(text: b.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      y += tp.height + (b.isHeading ? 12 : 20);
      tp.dispose();
    }
    return offsets;
  }

  double _scrollContentWidth() =>
      MediaQuery.sizeOf(context).width - 2 * _readingInset;

  double? _scrollOffsetForBlock(int? blockIndex) {
    final blocks = _structured?.allBlocks;
    if (blockIndex == null || blocks == null || blockIndex >= blocks.length) {
      return null;
    }
    final offsets = _blockOffsets(blocks, _scrollContentWidth());
    final topPad = MediaQuery.sizeOf(context).height * 0.1;
    return topPad + offsets[blockIndex];
  }

  /// The global block index currently at the top of the scroll viewport.
  int? _topVisibleBlockInScroll() {
    if (!_scrollController.hasClients) return null;
    final blocks = _structured?.allBlocks;
    if (blocks == null || blocks.isEmpty) return null;
    final offsets = _blockOffsets(blocks, _scrollContentWidth());
    final topPad = MediaQuery.sizeOf(context).height * 0.1;
    final pixels = _scrollController.position.pixels - topPad + 2;
    var index = 0;
    for (var i = 0; i < offsets.length; i++) {
      if (offsets[i] <= pixels) index = i;
    }
    return index;
  }

  /// Reads which block the *current* mode is showing, so we can re-anchor the
  /// other mode to the same content on switch.
  int? _captureAnchorBlock() {
    if (_settings.mode == ReaderMode.paginated) {
      final pages = _pages;
      if (pages == null || pages.isEmpty) return null;
      final pageIndex = (_currentPage - 1).clamp(0, pages.length - 1);
      return pages[pageIndex].first.$2;
    }
    if (_settings.mode == ReaderMode.scroll) {
      return _topVisibleBlockInScroll();
    }
    return null;
  }

  /// The page whose block range contains [blockIndex], else -1.
  int _pageForBlock(int blockIndex, List<List<(TextBlock, int)>> pages) {
    for (var pi = 0; pi < pages.length; pi++) {
      final p = pages[pi];
      if (blockIndex >= p.first.$2 && blockIndex <= p.last.$2) return pi;
    }
    return -1;
  }

  Widget _paginatedView() {
    _ensurePaginated();
    final pages = _pages;
    if (pages == null || pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // Land on the block the reader was on before switching (e.g. scroll ->
    // paginated). Fall back to the progress fraction.
    var initial = pages.length > 1 ? (_progress * (pages.length - 1)).round().clamp(0, pages.length - 1) : 0;
    if (_anchorBlock != null) {
      final byBlock = _pageForBlock(_anchorBlock!, pages);
      if (byBlock >= 0) initial = byBlock;
      _anchorBlock = null;
    }
    return _SinglePageView(
      key: ValueKey('book-${_pagesKey ?? ''}'),
      pages: pages,
      settings: _settings,
      controller: _bookController,
      initialPage: initial,
      onPageChanged: (i, total) => _onPageChanged(i, total),
      onToggleChrome: _toggleChrome,
    );
  }

  Widget _buildBlock(TextBlock block, int globalIndex) {
    final isHeading = block.isHeading;
    final highlightColor = _highlights[globalIndex];
    final style = isHeading ? _headingStyle : _bodyStyle;
    return Padding(
      padding: EdgeInsets.only(bottom: isHeading ? 12 : 20),
      child: GestureDetector(
        onLongPressStart: (details) => _onLongPress(globalIndex, block, details),
        child: Container(
          color: highlightColor != null ? _parseColor(highlightColor) : null,
          child: Text(block.text, style: style, textAlign: _settings.textAlign),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- pagination

  /// Dimensions of the single page and its text area. The page fills the whole
  /// reader width at full screen height. The text area is padded so it clears
  /// the overlay header/footer and leaves room for the page number.
  ({double pageW, double pageH, double textW, double textH}) _bookGeometry(
      Size screen) {
    const padX = 36.0;
    const padTop = 88.0;
    const padBottom = 160.0;
    final pageW = screen.width;
    final pageH = screen.height;
    final textW = (pageW - padX * 2).clamp(80.0, 1200.0);
    final textH = (pageH - padTop - padBottom).clamp(80.0, 2000.0);
    return (pageW: pageW, pageH: pageH, textW: textW, textH: textH);
  }

  String _paginateKey() {
    final g = _bookGeometry(MediaQuery.sizeOf(context));
    return '${_settings.fontFamily}|${_fontSize.toStringAsFixed(2)}|'
        '${_lineSpacing.toStringAsFixed(3)}|'
        '${g.pageW.toStringAsFixed(1)}|${g.pageH.toStringAsFixed(1)}|'
        '${g.textW.toStringAsFixed(1)}|${g.textH.toStringAsFixed(1)}';
  }

  /// Lazily (re)computes the page layout. Measurement is time-sliced across
  /// frames so the UI thread never blocks, and the result is cached keyed by
  /// the settings that affect layout, so taps/builds don't re-paginate.
  void _ensurePaginated() {
    if (!_reflowAvailable || _settings.mode != ReaderMode.paginated) return;
    final key = _paginateKey();
    if (_pages != null && _pagesKey == key) return;
    if (_paginating) return;
    _paginating = true;
    _pages = null;
    _paginateInChunks(key);
  }

  void _paginateInChunks(String key) {
    final blocks = _structured!.allBlocks;
    if (blocks.isEmpty) {
      _pages = [];
      _pagesKey = key;
      _paginating = false;
      return;
    }
    final g = _bookGeometry(MediaQuery.sizeOf(context));
    final width = g.textW;
    // Leave a small safety margin under the measured text height so pages
    // never clip the last line if rendered metrics drift from the measured
    // ones (async font loads etc.).
    final height = g.textH - 16;
    final pages = <List<(TextBlock, int)>>[];
    var current = <(TextBlock, int)>[];
    var used = 0.0;
    var i = 0;

    _paginateTimer?.cancel();
    _paginateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final deadline = DateTime.now().add(const Duration(milliseconds: 8));
      while (i < blocks.length && DateTime.now().isBefore(deadline)) {
        final b = blocks[i];
        final style = b.isHeading ? _headingStyle : _bodyStyle;
        final tp = TextPainter(
          text: TextSpan(text: b.text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        final blockHeight = tp.height + (b.isHeading ? 12 : 20);
        tp.dispose();

        if (blockHeight > height) {
          if (current.isNotEmpty) {
            pages.add(current);
            current = <(TextBlock, int)>[];
            used = 0;
          }
          final chunks = _splitParagraph(b, width, height);
          for (final chunk in chunks) {
            pages
                .add([(TextBlock(kind: b.kind, text: chunk, level: b.level), i)]);
          }
        } else {
          if (current.isNotEmpty && used + blockHeight > height) {
            pages.add(current);
            current = <(TextBlock, int)>[];
            used = 0;
          }
          current.add((b, i));
          used += blockHeight;
        }
        i++;
      }
      if (i >= blocks.length) {
        timer.cancel();
        _paginateTimer = null;
        if (current.isNotEmpty) pages.add(current);
        if (!mounted) return;
        setState(() {
          _pages = pages;
          _pagesKey = key;
          _paginating = false;
        });
      }
    });
  }

  List<String> _splitParagraph(TextBlock block, double width, double height) {
    final style = block.isHeading ? _headingStyle : _bodyStyle;
    final result = <String>[];
    var remaining = block.text;
    var guard = 0;
    while (remaining.isNotEmpty && guard++ < 500) {
      var lo = 1;
      var hi = remaining.length;
      var best = 1;
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final tp = TextPainter(
          text: TextSpan(text: remaining.substring(0, mid), style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        final fits = tp.height <= height;
        tp.dispose();
        if (fits) {
          best = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      var end = best;
      if (end < remaining.length) {
        var wordBoundary = end;
        while (wordBoundary > 0 && remaining[wordBoundary - 1] != ' ') {
          wordBoundary--;
        }
        if (wordBoundary > 0) end = wordBoundary;
      }
      result.add(remaining.substring(0, end).trimRight());
      remaining = remaining.substring(end).trimLeft();
    }
    return result.isEmpty ? [block.text] : result;
  }

  // --------------------------------------------------------------- progress

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.maxScrollExtent > 0) {
      final p = (n.metrics.pixels / n.metrics.maxScrollExtent).clamp(0.0, 1.0);
      _updateProgress(p);
    }
    return false;
  }

  void _onPageChanged(int index, int total) {
    if (total <= 1) {
      _updateProgress(1.0);
      return;
    }
    if (index + 1 != _currentPage || total != _pageCount) {
      setState(() {
        _currentPage = index + 1;
        _pageCount = total;
      });
    }
    _updateProgress(index / (total - 1));
  }

  void _updateProgress(double p) {
    if ((p - _progress).abs() < 0.005) return;
    _progressNotifier.value = p;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      _booksService.saveProgress(widget.book.id, fraction: _progress);
    });
  }

  // ------------------------------------------------------------- highlight

  void _onLongPress(int index, TextBlock block, LongPressStartDetails details) {
    HapticFeedback.selectionClick();
    final box = _readingKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(details.globalPosition) ??
        Offset(MediaQuery.sizeOf(context).width / 2, 120);
    setState(() {
      _highlightMenu = _HighlightMenuState(
        blockIndex: index,
        anchor: block.text,
        position: local,
      );
    });
  }

  Widget _buildHighlightMenu() {
    final menu = _highlightMenu!;
    final width = MediaQuery.sizeOf(context).width;
    final left = (menu.position.dx - 130).clamp(16.0, width - 300.0);
    return Positioned(
      left: left,
      top: (menu.position.dy - 64).clamp(24.0, double.infinity),
      child: _HighlightMenu(
        colors: const ['#FCE7F3', '#FEF08A', '#BBF7D0', '#BFDBFE'],
        onColor: (hex) => _applyHighlight(hex),
        onNote: _addNote,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: menu.anchor));
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
    setState(() {
      _highlights[menu.blockIndex] = hex;
      _highlightMenu = null;
    });
    _booksService.api.post('/sync/annotations', body: {
      'book_id': widget.book.id,
      'kind': 'highlight',
      'anchor': menu.anchor,
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
    if (note == null || note.trim().isEmpty) {
      if (mounted) setState(() => _highlightMenu = null);
      return;
    }
    setState(() => _highlightMenu = null);
    _booksService.api.post('/sync/annotations', body: {
      'book_id': widget.book.id,
      'kind': 'note',
      'anchor': menu.anchor,
      'note_text': note.trim(),
    });
  }

  Color _parseColor(String hex) {
    final v = int.parse('FF${hex.replaceAll('#', '')}', radix: 16);
    return Color(v).withValues(alpha: 0.45);
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
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
          ),
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
              pageCount: _pageCount,
              bookmarked: _bookmarked,
              background: _settings.atmosphere.background,
              text: _settings.atmosphere.text,
              accent: _settings.atmosphere.accent,
              onSeek: (v) {
                _updateProgress(v);
                _scrollToProgress(v);
              },
              onAppearance: _openAppearance,
              onSearch: _openSearch,
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

  void _scrollToProgress(double fraction) {
    if (!_reflowAvailable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_settings.mode == ReaderMode.paginated) {
        final pages = _pages;
        if (pages == null || pages.isEmpty) return;
        final target = (fraction * (pages.length - 1))
            .round()
            .clamp(0, pages.length - 1);
        _bookController.goToPage(target);
        _onPageChanged(target, pages.length);
        return;
      }
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
            fraction * _scrollController.position.maxScrollExtent);
      }
    });
  }

  /// Opens the "Appearance" sheet (bottom sheet, max 90% height) matching the
  /// AnyShelf design. The reader stays visible and dimmed behind it, so the
  /// settings never hide the book entirely.
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
          reflowAvailable: _reflowAvailable,
          onChanged: _updateSettings,
        ),
      ),
    );
  }

  Future<void> _openSearch() async {
    if (!_reflowAvailable) return;
    final blocks = _structured!.allBlocks;
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
    if (query == null || query.trim().isEmpty) return;

    final q = query.trim().toLowerCase();
    final matches = <(int, TextBlock)>[];
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].text.toLowerCase().contains(q)) matches.add((i, blocks[i]));
    }
    if (matches.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No matches')));
      return;
    }
    if (!mounted) return;

    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final chosen = await showDialog<(int, TextBlock)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${matches.length} result${matches.length == 1 ? '' : 's'}'),
        children: [
          for (final m in matches.take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m),
              child: Text(
                m.$2.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: SereneType.uiBody.copyWith(color: colors.onSurface),
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;

    if (_settings.mode == ReaderMode.scroll) {
      _jumpToBlock(chosen.$1);
    } else {
      _jumpToPageContaining(chosen.$1);
    }
  }

  void _jumpToBlock(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      var offset = 0.0;
      final blocks = _structured!.allBlocks;
      final width = MediaQuery.sizeOf(context).width - (2 * _readingInset);
      for (var i = 0; i < index && i < blocks.length; i++) {
        final b = blocks[i];
        final style = b.isHeading ? _headingStyle : _bodyStyle;
        final tp = TextPainter(
          text: TextSpan(text: b.text, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        offset += tp.height + (b.isHeading ? 12 : 20);
        tp.dispose();
      }
      _scrollController.animateTo(
        (offset - 80).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  void _jumpToPageContaining(int index) {
    final pages = _pages;
    if (pages == null) return;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].any((e) => e.$2 == index)) {
        _bookController.goToPage(i);
        _onPageChanged(i, pages.length);
        return;
      }
    }
  }
}

class _HighlightMenuState {
  final int blockIndex;
  final String anchor;
  final Offset position;
  const _HighlightMenuState({
    required this.blockIndex,
    required this.anchor,
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

/// The reader's bottom chrome: a scrubbable progress slider with percent/pages
/// labels and a row of action buttons (typography, search, bookmark, text to
/// speech). Matches the AnyShelf immersive-reader design.
class _ReaderFooter extends StatelessWidget {
  final double progress;
  final int pageCount;
  final bool bookmarked;
  final Color background;
  final Color text;
  final Color accent;
  final ValueChanged<double> onSeek;
  final VoidCallback onAppearance;
  final VoidCallback onSearch;
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
    required this.onAppearance,
    required this.onSearch,
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
                  child: Text(
                    pages,
                    textAlign: TextAlign.left,
                    style: SereneType.labelSm.copyWith(color: muted),
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
                  tooltip: 'Highlights &amp; Notes',
                  badge: importCount > 0 ? '$importCount' : null,
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

/// Drives the single-page reader from the reader chrome (seekbar jumps, search
/// navigation).
class _BookController {
  _SinglePageViewState? _state;

  void nextPage() => _state?.flipForward();
  void previousPage() => _state?.flipBackward();
  void goToPage(int pageIndex) => _state?.jumpToPage(pageIndex);
}

/// The paginated reading surface: one full-screen paper page at a time, turned
/// with a book-like 3D page-flip around the left spine. Swipe left/right to
/// turn; a quick tap still toggles the chrome (handled by the outer pointer
/// listener).
class _SinglePageView extends StatefulWidget {
  final List<List<(TextBlock, int)>> pages;
  final ReaderSettings settings;
  final _BookController controller;
  final int initialPage;
  final void Function(int pageIndex, int total) onPageChanged;
  final VoidCallback onToggleChrome;
  const _SinglePageView({
    super.key,
    required this.pages,
    required this.settings,
    required this.controller,
    required this.initialPage,
    required this.onPageChanged,
    required this.onToggleChrome,
  });

  @override
  State<_SinglePageView> createState() => _SinglePageViewState();
}

class _SinglePageViewState extends State<_SinglePageView>
    with TickerProviderStateMixin {
  late int _currentPage;
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _forward = true;
  bool _busy = false;
  double _dragProgress = 0;
  double _dragStartX = 0;

  int get _maxPage => math.max(0, widget.pages.length - 1);
  bool get _canFlipForward => _currentPage < _maxPage;
  bool get _canFlipBackward => _currentPage > 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(0, _maxPage).toInt();
    widget.controller._state = this;
    _flip.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishFlip();
    });
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _flip.dispose();
    super.dispose();
  }

  void _finishFlip() {
    if (!mounted) return;
    setState(() {
      _currentPage = (_currentPage + (_forward ? 1 : -1)).clamp(0, _maxPage);
      _busy = false;
      _flip.value = 0;
    });
    widget.onPageChanged(_currentPage, widget.pages.length);
  }

  void flipForward() {
    if (_busy || !_canFlipForward) return;
    setState(() {
      _forward = true;
      _busy = true;
    });
    _flip.forward(from: 0);
  }

  void flipBackward() {
    if (_busy || !_canFlipBackward) return;
    setState(() {
      _forward = false;
      _busy = true;
    });
    _flip.forward(from: 0);
  }

  void jumpToPage(int pageIndex) {
    final target = pageIndex.clamp(0, _maxPage).toInt();
    if (target == _currentPage) return;
    setState(() {
      _currentPage = target;
      _busy = false;
      _flip.value = 0;
    });
    widget.onPageChanged(target, widget.pages.length);
  }

  void _onDragStart(DragStartDetails d) {
    if (_busy) return;
    _dragStartX = d.globalPosition.dx;
    _dragProgress = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_busy) return;
    final dx = d.globalPosition.dx - _dragStartX;
    _forward = dx < 0;
    final can = _forward ? _canFlipForward : _canFlipBackward;
    if (!can) {
      _flip.value = 0;
      _dragProgress = 0;
      return;
    }
    final w = MediaQuery.sizeOf(context).width;
    final delta = _forward ? -dx : dx;
    _dragProgress = (delta / (w * 0.6)).clamp(0.0, 1.0);
    _flip.value = _dragProgress;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_busy) return;
    final can = _forward ? _canFlipForward : _canFlipBackward;
    if (!can) {
      _flip.animateBack(0, duration: const Duration(milliseconds: 250));
      _dragProgress = 0;
      return;
    }
    if (_dragProgress >= 0.45) {
      setState(() => _busy = true);
      _flip.animateTo(
        1,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _flip.animateBack(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    _dragProgress = 0;
  }

  void _onTapUp(TapUpDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final x = d.globalPosition.dx;
    // Left/right thirds turn pages like a real book; the centre toggles chrome.
    if (x < w * 0.3) {
      flipBackward();
    } else if (x > w * 0.7) {
      flipForward();
    } else {
      widget.onToggleChrome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    final paper = _paperFor(widget.settings.atmosphere);
    const leafPadding = EdgeInsets.fromLTRB(36, 88, 36, 160);

    Widget buildPage(int idx, {bool showPageNumber = true}) => _BookLeaf(
          blocks: pages[idx],
          settings: widget.settings,
          paper: paper,
          pageNumber: idx + 1,
          showPageNumber: showPageNumber,
          padding: leafPadding,
        );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () {
        if (!_busy) {
          _flip.animateBack(0, duration: const Duration(milliseconds: 250));
          _dragProgress = 0;
        }
      },
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final angle = _flip.value * math.pi;
          final progress = _flip.value;
          final showBack = angle > math.pi / 2;
          final turning = _busy || progress > 0;
          // 0..1..0 peak at mid-flip: drives the page swell and spine crease.
          final wave = math.sin(progress * math.pi);

          // Book page turn like the web reader's StPageFlip: the leaf rotates
          // around the spine while the perspective entry makes it swell toward
          // the reader at mid-flip (translate moves the leaf along the view Z).
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0022)
            ..translateByDouble(0.0, 0.0, wave * 110.0, 1.0)
            ..rotateX(_forward ? angle * 0.06 : -angle * 0.06)
            ..rotateY(_forward ? -angle : angle);

          // Stationary page beneath the turning leaf.
          int underlay;
          if (turning && _forward) {
            underlay = math.min(_currentPage + 1, _maxPage);
          } else if (turning && !_forward) {
            underlay = math.max(_currentPage - 1, 0);
          } else {
            underlay = _currentPage;
          }

          // The turning leaf: front face (current page) becomes the back face
          // (the page being revealed) after the halfway point of the rotation.
          Widget? leaf;
          if (turning) {
            final frontIdx = _forward ? _currentPage : math.max(_currentPage - 1, 0);
            final backIdx = _forward
                ? math.min(_currentPage + 1, _maxPage)
                : _currentPage;
            final faceIdx = showBack ? backIdx : frontIdx;
            Widget face = buildPage(faceIdx, showPageNumber: !showBack);
            if (showBack) {
              // The far side of the leaf: mirrored and catching less light.
              face = ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.9, 0, 0, 0, 0,
                  0, 0.9, 0, 0, 0,
                  0, 0, 0.9, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
                  child: face,
                ),
              );
            }
            // The leaf stays flat like a real printed page (StPageFlip pages
            // don't bend); the only fold is the dark crease right at the spine
            // where the leaf pivots. Rounded corners match the web reader.
            leaf = ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: face),
                  // crease along the spine where the page bends over
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: _forward
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            end: Alignment.center,
                            colors: [
                              Colors.black.withValues(alpha: 0.34 * wave),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // faint sheen sweeping the leaf as it turns
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: _forward
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            end: _forward
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.10 * wave),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // stationary page beneath the turning leaf
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: buildPage(underlay, showPageNumber: !turning),
                ),
              ),
              // folded bottom corner of the current page, like the web reader's
              // showPageCorners
              if (!turning)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: const Size(22, 22),
                    painter: _CornerFoldPainter(paper),
                  ),
                ),
              // left spine thickness: dark binding edge for a real book feel
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.10),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
              // right-hand page-stack edge: a few thin leaf edges giving the
              // open book thickness and depth (hidden while a leaf is turning)
              if (!turning && _currentPage < _maxPage)
                for (var k = 1; k <= 3; k++)
                  Positioned(
                    right: -1.0 - k * 1.5,
                    top: 1.0 + k,
                    bottom: 1.0 - k,
                    width: 3,
                    child: IgnorePointer(
                      child: Container(
                        color: paper.withValues(alpha: 0.55 - k * 0.12),
                      ),
                    ),
                  ),
              // turning leaf
              if (leaf != null)
                Positioned.fill(
                  child: ClipRect(
                    child: Transform(
                      alignment: _forward
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      transform: transform,
                      child: leaf,
                    ),
                  ),
                ),
              // curved shadow cast onto the stationary page being covered; the
              // gradient sits at the fold so it moves as the leaf turns
              if (turning && progress > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _forward
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          end: Alignment.center,
                          colors: [
                            Colors.black.withValues(alpha: 0.18 * progress),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // subtle spine shadow on the left edge
              if (!turning)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The small triangle of paper turned up at the outer corner of a page — the
/// web reader's `showPageCorners` look.
class _CornerFoldPainter extends CustomPainter {
  final Color paper;
  const _CornerFoldPainter(this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    const fold = 20.0;
    final w = size.width;
    final h = size.height;
    final corner = Offset(w, h);
    final left = Offset(w - fold, h);
    final top = Offset(w, h - fold);

    // soft shadow the turned-up corner casts onto the page beneath
    final shadow = Path()
      ..moveTo(left.dx + 3, left.dy)
      ..lineTo(top.dx, top.dy + 3)
      ..lineTo(corner.dx, corner.dy)
      ..close();
    canvas.drawPath(
      shadow,
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    // the turned-up back of the page corner
    final flap = Path()
      ..moveTo(corner.dx, corner.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(top.dx, top.dy)
      ..close();
    canvas.drawPath(
      flap,
      Paint()..color = paper.withValues(alpha: 0.98),
    );

    // crease of the fold
    canvas.drawLine(
      left,
      top,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CornerFoldPainter oldDelegate) =>
      oldDelegate.paper != paper;
}

/// A single paper page: padded text column plus a page number at the bottom
/// right corner, like a real printed page.
class _BookLeaf extends StatelessWidget {
  final List<(TextBlock, int)> blocks;
  final ReaderSettings settings;
  final Color paper;
  final int pageNumber;
  final bool showPageNumber;
  final EdgeInsets padding;
  const _BookLeaf({
    required this.blocks,
    required this.settings,
    required this.paper,
    required this.pageNumber,
    this.showPageNumber = true,
    this.padding = const EdgeInsets.fromLTRB(36, 88, 36, 160),
  });

  @override
  Widget build(BuildContext context) {
    final text = settings.atmosphere.text;
    final bodyStyle = GoogleFonts.getFont(
      settings.fontFamily,
      textStyle: TextStyle(
        fontSize: settings.fontSize,
        height: settings.lineHeight.value,
        color: text,
      ),
    );
    final headingStyle = bodyStyle.copyWith(
      fontSize: settings.fontSize * 1.3,
      fontWeight: FontWeight.w700,
    );
    return Container(
      color: paper,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in blocks)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: b.$1.isHeading ? 12 : 20,
                      ),
                      child: Text(
                        b.$1.text,
                        textAlign: settings.textAlign,
                        style: b.$1.isHeading ? headingStyle : bodyStyle,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showPageNumber)
            Positioned(
              right: 24,
              bottom: 18,
              child: Text(
                '$pageNumber',
                style: SereneType.labelSm.copyWith(
                  color: text.withValues(alpha: 0.5),
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
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
    _controller.dispose();
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
    // Compute the fraction from the real bar width (LayoutBuilder), not the
    // whole screen -- the footer squeezes the bar between a percent label and
    // a page-count label, so using screen width makes taps/drags drift and
    // never reach 100%.
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
                  FractionallySizedBox(
                    widthFactor: f == 0 ? 0.001 : f,
                    alignment: Alignment.centerRight,
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

/// The "Highlights &amp; Notes" sheet shown from the reader footer. Lists every
/// annotation on the book -- reader-created highlights/notes and native PDF
/// annotations imported at extraction time (badged "Imported from PDF").
/// Tapping a highlight jumps to its place in the reflowed text.
class _AnnotationsSheet extends StatelessWidget {
  final List<Annotation> annotations;
  final List<TextBlock> blocks;
  final ReadingAtmosphere atmosphere;
  final ValueChanged<String> onTapHighlight;

  const _AnnotationsSheet({
    required this.annotations,
    required this.blocks,
    required this.atmosphere,
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
                child: Text('Highlights &amp; Notes',
                    style: SereneType.title.copyWith(color: text)),
              ),
              if (annotations.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                  child: Text(
                    'No highlights or notes yet. Highlight a passage to add '
                    'one, or open this book in a PDF reader to import its '
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
                    separatorBuilder: (_, __) =>
                        SizedBox(height: 8),
                    itemBuilder: (context, i) => _AnnotationTile(
                      annotation: annotations[i],
                      text: text,
                      muted: muted,
                      hint: hint,
                      accent: atmosphere.accent,
                      canTap: blocks.isNotEmpty,
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

/// A single annotation in the Highlights &amp; Notes sheet: colored marker,
/// the quoted text or the note body, and an "Imported from PDF" badge when the
/// annotation came from the original document rather than the reader.
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
    final color = _AnnotationsSheet._parseColor(
      annotation.color,
      accent,
    );
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

