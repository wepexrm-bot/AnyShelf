import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/book.dart';
import '../models/reader_settings.dart';
import '../services/books_service.dart';
import '../services/settings_service.dart';
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
  final PageController _pageController = PageController();

  late ReaderSettings _settings = ReaderSettings.defaults();
  StructuredText? _structured;
  String? _pdfUrl; // resolved from GET /books/{id} (list omits pdf_url)
  bool _uiVisible = false;
  bool _bookmarked = false;
  String? _bookmarkId; // backend annotation id of the current bookmark, if any
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;

  // cached, time-sliced pagination state
  List<List<(TextBlock, int)>>? _pages;
  String? _pagesKey;
  Timer? _paginateTimer;
  bool _paginating = false;

  // highlight state
  Map<int, String> _highlights = {}; // global block index -> color hex
  _HighlightMenuState? _highlightMenu;

  // page tracking for the footer (paginated mode)
  int _currentPage = 0;
  int _pageCount = 0;

  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

  double get _progress => _progressNotifier.value;

  bool get _reflowAvailable => widget.book.reflowAvailable && _structured != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _paginateTimer?.cancel();
    _scrollController.dispose();
    _pageController.dispose();
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
        _pdfUrl = detail.pdfUrl;
        _progressNotifier.value = progress;
        _bookmarked = bookmark != null;
        _bookmarkId = bookmark;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _updateSettings(ReaderSettings next) {
    setState(() => _settings = next);
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
    if (!_reflowAvailable) {
      return _fixedPdfView();
    }
    return _settings.mode == ReaderMode.scroll
        ? _scrollView()
        : _paginatedView();
  }

  Widget _fixedPdfView() {
    final url = _pdfUrl;
    return Container(
      color: _settings.atmosphere.background,
      child: url == null || url.isEmpty
          ? Center(
              child: Text('PDF unavailable',
                  style: SereneType.uiBody
                      .copyWith(color: _settings.atmosphere.text)),
            )
          : SfPdfViewer.network(url),
    );
  }

  Widget _scrollView() {
    final blocks = _structured!.allBlocks;
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

  Widget _paginatedView() {
    _ensurePaginated();
    final pages = _pages;
    if (pages == null || pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onPageScroll,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: pages.length,
        onPageChanged: (i) => _onPageChanged(i, pages.length),
        itemBuilder: (context, i) => Padding(
          padding: EdgeInsets.fromLTRB(
            _readingInset,
            MediaQuery.sizeOf(context).height * 0.1,
            _readingInset,
            MediaQuery.sizeOf(context).height * 0.08,
          ),
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final b in pages[i]) _buildBlock(b.$1, b.$2),
            ],
          ),
        ),
      ),
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

  String _paginateKey() {
    final size = MediaQuery.sizeOf(context);
    return '${_settings.fontFamily}|${_fontSize.toStringAsFixed(2)}|'
        '${_lineSpacing.toStringAsFixed(3)}|${_readingInset.toStringAsFixed(1)}|'
        '${size.width.toStringAsFixed(1)}|${size.height.toStringAsFixed(1)}';
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
    final size = MediaQuery.sizeOf(context);
    final width = size.width - (2 * _readingInset);
    final height = size.height * 0.78;
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

  bool _onPageScroll(ScrollNotification n) => false;

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
        if (pages == null || pages.isEmpty || !_pageController.hasClients) {
          return;
        }
        final target = (fraction * (pages.length - 1)).round();
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
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
        _pageController.animateToPage(
          i,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
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
  const _FooterAction({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 28, color: color),
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
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (d) => onSeek(_fractionFromX(context, d.localPosition.dx)),
      onHorizontalDragUpdate: (d) =>
          onSeek(_fractionFromX(context, d.localPosition.dx)),
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
  }

  double _fractionFromX(BuildContext context, double dx) {
    final width = MediaQuery.sizeOf(context).width - 32 - 24;
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }
}

