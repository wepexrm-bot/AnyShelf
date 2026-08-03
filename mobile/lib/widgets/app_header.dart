import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../screens/reader_screen.dart';
import '../services/books_service.dart';
import '../services/ui_mode_controller.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import 'sync_indicator.dart';

/// Branded top bar: filled cloud glyph + "AnyShelf" wordmark (Playfair, accent
/// green) on the left, a library-wide search field in the middle, an optional
/// light/dark toggle, and the trailing widget (by default the cloud sync
/// status). Reads "top app bar" in the design. Sits under the notification
/// panel, so the content is wrapped in a SafeArea.
class AppHeader extends StatelessWidget {
  final Widget? trailing;
  final bool showSync;
  final bool showThemeToggle;
  final EdgeInsetsGeometry padding;
  const AppHeader({
    super.key,
    this.trailing,
    this.showSync = true,
    this.showThemeToggle = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.82),
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.25))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/logo.png', width: 28, height: 28),
              ),
              const SizedBox(width: 8),
              Text(
                'AnyShelf',
                style: SereneType.headlineMobile.copyWith(
                  color: colors.accentTeal,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(child: _HeaderSearch()),
              const SizedBox(width: 12),
              if (showThemeToggle) ...[
                Consumer<UiModeController>(
                  builder: (context, uiMode, _) => IconButton(
                    onPressed: uiMode.toggle,
                    tooltip: uiMode.isDark ? 'Switch to light mode' : 'Switch to dark mode',
                    icon: Icon(
                      uiMode.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              trailing ?? (showSync ? const SyncIndicator() : const SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// A search field that queries the whole library. Matches (title/author) are
/// shown in a dropdown panel anchored just below the field; tapping one opens
/// the reader. Works from any screen because every page shares [AppHeader].
class _HeaderSearch extends StatefulWidget {
  const _HeaderSearch();

  @override
  State<_HeaderSearch> createState() => _HeaderSearchState();
}

class _HeaderSearchState extends State<_HeaderSearch> {
  final TextEditingController _ctl = TextEditingController();
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  final GlobalKey _fieldKey = GlobalKey();
  final LayerLink _link = LayerLink();
  Timer? _debounce;
  List<Book> _results = const [];
  bool _loading = false;
  double? _panelWidth;
  double? _panelHeight;
  OverlayEntry? _entry;

  bool get _showPanel =>
      _focus.hasFocus && _ctl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _ctl.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {});
    _updateOverlay();
  }

  void _measureAnchor() {
    final ctx = _fieldKey.currentContext;
    final box = ctx?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _panelWidth = box.size.width;
      _panelHeight = box.size.height;
    }
  }

  void _updateOverlay() {
    _removeOverlay();
    if (!_showPanel) return;
    _measureAnchor();
    if (_panelHeight == null) return;
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        offset: Offset(0, (_panelHeight ?? 0) + 8),
        child: _buildPanel(),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      _updateOverlay();
      return;
    }
    setState(() => _loading = true);
    _updateOverlay();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    try {
      final books = await BooksService().list();
      final q = query.toLowerCase();
      final matches = books
          .where((b) =>
              b.title.toLowerCase().contains(q) ||
              (b.author ?? '').toLowerCase().contains(q))
          .take(8)
          .toList();
      if (!mounted) return;
      setState(() {
        _results = matches;
        _loading = false;
      });
      _updateOverlay();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
      _updateOverlay();
    }
  }

  void _openBook(Book book) {
    _ctl.clear();
    _focus.unfocus();
    setState(() {
      _results = const [];
      _loading = false;
    });
    _removeOverlay();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  Widget _buildPanel() {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final width = _panelWidth ?? MediaQuery.sizeOf(context).width - 48;
    Widget content;
    if (_loading) {
      content = Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ),
      );
    } else if (_results.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No books found',
            style: SereneType.labelMd.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    } else {
      content = ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final b in _results)
            ListTile(
              dense: true,
              leading: _thumb(b, colors),
              title: Text(
                b.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SereneType.labelMd.copyWith(color: colors.onSurface),
              ),
              subtitle: b.author == null || b.author!.isEmpty
                  ? null
                  : Text(
                      b.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.labelSm.copyWith(
                          color: colors.onSurfaceVariant),
                    ),
              trailing: Icon(Icons.chevron_right,
                  size: 18, color: colors.outline),
              onTap: () => _openBook(b),
            ),
        ],
      );
    }
    return Material(
      color: colors.surfaceContainerLow,
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: width,
        constraints: const BoxConstraints(maxHeight: 360),
        child: content,
      ),
    );
  }

  Widget _thumb(Book b, SereneColorScheme colors) {
    final url = b.coverUrl;
    Widget inner;
    if (url != null && url.isNotEmpty) {
      inner = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(colors),
      );
    } else {
      inner = _placeholder(colors);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(width: 34, height: 46, child: inner),
    );
  }

  Widget _placeholder(SereneColorScheme colors) => ColoredBox(
        color: colors.surfaceContainerHigh,
        child: Center(
          child: Icon(Icons.menu_book, size: 16, color: colors.outlineVariant),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return CompositedTransformTarget(
      link: _link,
      child: TextField(
        key: _fieldKey,
        controller: _ctl,
        focusNode: _focus,
        onChanged: _onChanged,
        style: SereneType.uiBody.copyWith(fontSize: 14, color: colors.onSurface),
        decoration: InputDecoration(
          hintText: 'Search your library',
          hintStyle: SereneType.uiBody
              .copyWith(fontSize: 14, color: colors.onSurfaceVariant),
          prefixIcon:
              Icon(Icons.search, size: 20, color: colors.onSurfaceVariant),
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colors.primary),
          ),
        ),
      ),
    );
  }
}
