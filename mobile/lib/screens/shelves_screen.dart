import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import '../services/library_refresh.dart';
import '../services/shelves_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import '../widgets/book_cover.dart';
import '../widgets/shelf_cover.dart';

/// The Shelves destination: a grid of your shelves (plus a create card), each
/// opening a detail view where books can be added, removed, or the shelf
/// edited/deleted — mirroring the web Shelves page.
class ShelvesScreen extends StatefulWidget {
  final ValueChanged<Book> onOpenBook;
  const ShelvesScreen({super.key, required this.onOpenBook});

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  final _shelvesService = ShelvesService();
  List<Shelf> _shelves = [];
  List<Book> _books = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _syncFromStore();
    LibraryRefresh.instance.addListener(_onLibraryChanged);
    _ensureLoaded();
  }

  @override
  void dispose() {
    LibraryRefresh.instance.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// Copies the shared library snapshot (books + shelves) into this screen's
  /// local state. Safe to call during initState.
  void _syncFromStore() {
    final store = LibraryRefresh.instance;
    _books = store.books();
    _shelves = store.shelves ?? const [];
    _error = store.error;
    _loading = !store.hasData && store.isLoading;
  }

  void _onLibraryChanged() {
    if (!mounted) return;
    setState(_syncFromStore);
  }

  void _ensureLoaded() {
    final store = LibraryRefresh.instance;
    if (!store.hasLoaded) store.reload();
  }

  Future<void> _refresh() => LibraryRefresh.instance.reload();

  Future<void> _openDetail(Shelf shelf) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ShelfDetailScreen(
          shelf: shelf,
          books: _books,
          onOpenBook: widget.onOpenBook,
          service: _shelvesService,
        ),
      ),
    );
    if (changed == true) LibraryRefresh.instance.bump();
  }

  Future<void> _createShelf() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShelfFormDialog(
        service: _shelvesService,
        books: _books,
        // Optimistic: the shelf appears in the grid the moment it's saved.
        onSaved: (shelf) async {
          LibraryRefresh.instance.upsertShelf(shelf);
          LibraryRefresh.instance.bump();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final isTablet =
        MediaQuery.sizeOf(context).width >= SereneLayout.tabletBreakpoint;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _createShelf,
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.xl)),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: isTablet
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.endContained,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _books.isEmpty && _shelves.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                'Couldn\'t reach your library',
                style: SereneType.title.copyWith(color: colors.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: SereneType.uiBody
                    .copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Shelves',
                      style: SereneType.headlineMobile.copyWith(color: colors.onSurface)),
                  const SizedBox(height: 4),
                  Text(
                    '${_shelves.length} ${_shelves.length == 1 ? 'shelf' : 'shelves'} · ${_books.length} ${_books.length == 1 ? 'book' : 'books'} total',
                    style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == 0) {
                    return _CreateShelfCard(onTap: _createShelf);
                  }
                  final shelf = _shelves[index - 1];
                  return _ShelfCard(
                    shelf: shelf,
                    onTap: () => _openDetail(shelf),
                  );
                },
                childCount: _shelves.length + 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  final Shelf shelf;
  final VoidCallback onTap;
  const _ShelfCard({required this.shelf, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final base = shelfColorFromHex(shelf.color, fallback: colors.primary);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.all(SereneShape.lg),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    top: 4,
                    child: Transform.translate(
                      offset: const Offset(0, -3),
                      child: Transform.rotate(
                        angle: 0.012,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(SereneShape.md),
                            border: Border.all(color: colors.outlineVariant),
                            color: base.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ShelfCover(shelf: shelf, height: double.infinity),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(shelf.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SereneType.labelMd.copyWith(color: colors.onSurface)),
            const SizedBox(height: 2),
            Text(
              '${shelf.bookCount} ${shelf.bookCount == 1 ? 'book' : 'books'}',
              style: SereneType.uiBody.copyWith(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateShelfCard extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateShelfCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(SereneShape.lg),
          border: Border.all(width: 2, color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.surfaceContainerHigh,
              ),
              child: Icon(Icons.add, size: 28, color: colors.primary),
            ),
            const SizedBox(height: 12),
            Text('Create New Shelf',
                style: SereneType.labelMd.copyWith(color: colors.onSurface)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Organize your reading by theme, mood, or project',
                textAlign: TextAlign.center,
                style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShelfFormDialog extends StatefulWidget {
  final ShelvesService service;
  final List<Book> books;
  final Future<void> Function(Shelf shelf) onSaved;
  final Shelf? initial;
  const _ShelfFormDialog({
    required this.service,
    required this.books,
    required this.onSaved,
    this.initial,
  });

  @override
  State<_ShelfFormDialog> createState() => _ShelfFormDialogState();
}

class _ShelfFormDialogState extends State<_ShelfFormDialog> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _descCtl =
      TextEditingController(text: widget.initial?.description ?? '');
  late String _color = widget.initial?.color ?? kShelfColorPalette.first;
  late final Set<String> _selected = _initialBookIds();
  late final Set<String> _initialIds = Set<String>.from(_selected);
  bool _showCustom = false;
  Uint8List? _bannerBytes;
  String? _bannerName;
  bool _saving = false;

  Set<String> _initialBookIds() {
    final ids = <String>{};
    for (final id in widget.initial?.bookIds ?? const <String>[]) {
      ids.add(id);
    }
    for (final b in widget.initial?.books ?? const <ShelfBook>[]) {
      ids.add(b.id);
    }
    return ids;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    const typeGroup = XTypeGroup(
      label: 'Image',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bannerBytes = bytes;
      _bannerName = file.name;
    });
  }

  void _toggleBook(Book b) {
    setState(() {
      if (_selected.contains(b.id)) {
        _selected.remove(b.id);
      } else {
        _selected.add(b.id);
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    final description = _descCtl.text.trim().isEmpty
        ? null
        : _descCtl.text.trim();
    setState(() => _saving = true);
    try {
      final shelf = widget.initial != null
          ? await widget.service.update(
              widget.initial!.id,
              name: name,
              description: description,
              color: _color,
            )
          : await widget.service.create(
              name: name,
              description: description,
              color: _color,
            );
      final shelfId = shelf.id;
      if (_bannerBytes != null && _bannerName != null) {
        await widget.service.uploadBanner(shelfId,
            bytes: _bannerBytes!, filename: _bannerName!);
      }
      for (final b in widget.books) {
        final want = _selected.contains(b.id);
        final had = _initialIds.contains(b.id);
        if (want && !had) {
          await widget.service.addBook(shelfId, b.id);
        } else if (!want && had) {
          await widget.service.removeBook(shelfId, b.id);
        }
      }
      await widget.onSaved(shelf);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the shelf: $e')),
      );
    }
  }

  SereneColorScheme get _colors =>
      Theme.of(context).extension<SereneTheme>()!.colors;

  InputDecoration _inputDecoration({String hint = ''}) {
    final colors = _colors;
    return InputDecoration(
      hintText: hint,
      hintStyle: SereneType.uiBody.copyWith(fontSize: 14, color: colors.outline),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: _inputBorder(),
      enabledBorder: _inputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
    );
  }

  OutlineInputBorder _inputBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _colors.outlineVariant),
      );

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Dialog(
      backgroundColor: colors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(colors),
              const SizedBox(height: 20),
              _ShelfPreviewPanel(
                name: _nameCtl.text,
                color: _color,
                bannerBytes: _bannerBytes,
                bannerUrl: widget.initial?.bannerUrl,
              ),
              const SizedBox(height: 20),
              _fieldLabel(colors, 'Name'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtl,
                autofocus: true,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                decoration: _inputDecoration(hint: 'e.g. Sci-Fi Favorites'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _fieldLabel(colors, 'Description'),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtl,
                minLines: 3,
                maxLines: 4,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface, height: 1.5),
                decoration:
                    _inputDecoration(hint: "What's this shelf about?"),
              ),
              const SizedBox(height: 20),
              _fieldLabel(colors, 'Color'),
              const SizedBox(height: 6),
              _colorSwatches(colors),
              const SizedBox(height: 10),
              _customColorButton(colors),
              if (_showCustom) ...[
                const SizedBox(height: 8),
                _CustomColorPicker(
                  value: _color,
                  onChanged: (c) => setState(() => _color = c),
                ),
              ],
              const SizedBox(height: 20),
              _fieldLabel(colors, 'Cover image'),
              const SizedBox(height: 6),
              _coverZone(colors),
              const SizedBox(height: 20),
              _fieldLabel(
                      colors, 'Books in this shelf (${_selected.length})'),
              const SizedBox(height: 6),
              _bookPicker(colors),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed:
                        _nameCtl.text.trim().isEmpty || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                    icon: Icon(
                        widget.initial == null ? Icons.add : Icons.save,
                        size: 17),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : widget.initial == null
                              ? 'Create shelf'
                              : 'Save changes',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(SereneColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                    widget.initial == null ? Icons.add : Icons.edit,
                    size: 22,
                    color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                widget.initial == null ? 'Create New Shelf' : 'Edit Shelf',
                style: SereneType.title.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.initial == null
                    ? 'Name it, pick a color, and add a cover.'
                    : "Personalize this shelf's look and books.",
                style: SereneType.labelMd.copyWith(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, size: 20, color: colors.onSurfaceVariant),
          visualDensity: VisualDensity.compact,
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _fieldLabel(SereneColorScheme colors, String text) {
    return Text(
      text.toUpperCase(),
      style: SereneType.labelSm.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.04,
        color: colors.onSurfaceVariant,
      ),
    );
  }

  Widget _colorSwatches(SereneColorScheme colors) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in kShelfColorPalette)
          GestureDetector(
            onTap: () => setState(() {
              _color = c;
            }),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: shelfColorFromHex(c, fallback: colors.primary),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.transparent, width: 2),
                boxShadow: _color == c
                    ? [
                        BoxShadow(
                          color: colors.onSurface,
                          blurRadius: 0,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(Icons.check,
                  size: 18,
                  color: _color == c
                      ? Colors.white
                      : Colors.transparent),
            ),
          ),
      ],
    );
  }

  Widget _customColorButton(SereneColorScheme colors) {
    final isCustom = _showCustom || !kShelfColorPalette.contains(_color);
    return GestureDetector(
      onTap: () => setState(() => _showCustom = !_showCustom),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _showCustom
              ? const Color(0x12154212)
              : colors.surfaceContainerLowest,
          border: Border.all(
            color: _showCustom ? colors.primary : colors.outlineVariant,
            width: _showCustom ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isCustom
                    ? shelfColorFromHex(_color, fallback: colors.primary)
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: const [
                  BoxShadow(color: Color(0x22FFFFFF)),
                ],
                gradient: isCustom
                    ? null
                    : const SweepGradient(colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ]),
              ),
              child: const SizedBox.expand(),
            ),
            const SizedBox(width: 12),
            const Text('Custom color',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            AnimatedRotation(
              turns: _showCustom ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(Icons.expand_more,
                  size: 18,
                  color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverZone(SereneColorScheme colors) {
    final hasCover = _bannerBytes != null;
    return GestureDetector(
      onTap: _pickCover,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 132,
          color: colors.surfaceContainerLow,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _ShelfDashedPainter(
                    color: colors.outlineVariant, radius: 18),
              ),
              if (hasCover)
                Image.memory(_bannerBytes!, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        size: 26, color: colors.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Upload a cover image',
                      style: SereneType.labelMd.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'JPG or PNG, optional',
                      style: SereneType.labelSm.copyWith(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookPicker(SereneColorScheme colors) {
    if (widget.books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'No books uploaded yet — add them later from the shelf.',
          style: SereneType.labelSm
              .copyWith(fontSize: 13, color: colors.onSurfaceVariant),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 210,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: widget.books.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final b = widget.books[index];
            final checked = _selected.contains(b.id);
            return InkWell(
              onTap: () => _toggleBook(b),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (_) => _toggleBook(b),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      activeColor: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 30,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 3,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      child: Icon(Icons.auto_stories,
                          size: 16,
                          color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        b.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SereneType.labelMd.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The live shelf preview in the create/edit form, drawn like the web shelf
/// cards: the shelf colour (or banner) with a bottom gradient and the name in
/// white at the bottom-left.
class _ShelfPreviewPanel extends StatelessWidget {
  final String name;
  final String color;
  final Uint8List? bannerBytes;
  final String? bannerUrl;
  const _ShelfPreviewPanel({
    required this.name,
    required this.color,
    this.bannerBytes,
    this.bannerUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final base = shelfColorFromHex(color, fallback: colors.primary);
    Widget underlay;
    if (bannerBytes != null) {
      underlay = Image.memory(bannerBytes!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _gradientPlaceholder(colors, base));
    } else if (bannerUrl != null && bannerUrl!.isNotEmpty) {
      underlay = Image.network(bannerUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _gradientPlaceholder(colors, base));
    } else {
      underlay = _gradientPlaceholder(colors, base);
    }
    return Container(
      height: 148,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 22,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          underlay,
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x80000000)],
              ),
            ),
          ),
          Positioned(
            left: 18,
            bottom: 18,
            child: Text(
              name.trim().isEmpty ? 'Shelf name' : name.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.15,
                shadows: [
                  Shadow(
                    color: Color(0x73000000),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientPlaceholder(SereneColorScheme colors, Color base) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            base.withValues(alpha: 0.6),
            const Color(0xFF0D0F0D),
          ],
        ),
      ),
    );
  }
}

/// The web ShelfForm's custom color picker: an SV plane, a hue bar, and a hex
/// input. The field reports normalized strings so the form stores an exact
/// color even if it isn't in the palette.
class _CustomColorPicker extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _CustomColorPicker({required this.value, required this.onChanged});

  @override
  State<_CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<_CustomColorPicker> {
  late List<double> _hsv = _hexToHsv(widget.value);
  final FocusNode _hexFocus = FocusNode();
  late final TextEditingController _hexCtl =
      TextEditingController(text: _hsvToHex(_hsv[0], _hsv[1], _hsv[2]));

  @override
  void dispose() {
    _hexCtl.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _apply(double h, double s, double v) {
    final c = _hsvToHex(h, s, v);
    widget.onChanged(c);
    setState(() {
      _hsv = [h, s, v];
      if (!_hexFocus.hasFocus) _hexCtl.text = c.replaceAll('#', '').toUpperCase();
    });
  }

  Color _hexColor(String hex) =>
      Color(0xFF000000 | (int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0));

  void _onHexEdit(String raw) {
    final val = raw.replaceAll('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(val)) {
      final u = '#$val';
      final hsv = _hexToHsv(u);
      widget.onChanged(u);
      setState(() => _hsv = hsv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final h = _hsv[0], s = _hsv[1], v = _hsv[2];
    final hueSolid = _hexColor(_hsvToHex(h, 100, 100));
    final hueColors = [
      for (var d = 0; d <= 360; d += 60) _hexColor(_hsvToHex(d.toDouble(), 100, 100)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            return _svBox(w, h, s, v, hueSolid, colors);
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => _hueField(c.maxWidth, h, s, v, hueColors, colors),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hexColor(widget.value),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: const [
                  BoxShadow(color: Color(0x22FFFFFF)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hexCtl,
                focusNode: _hexFocus,
                onChanged: _onHexEdit,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 0.05,
                  color: colors.onSurface,
                  fontFamily: SereneType.uiBody.fontFamily,
                ),
                decoration: _hexInput(colors),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _svBox(double w, double h, double s, double v, Color hueSolid,
      SereneColorScheme colors) {
    const boxH = 120.0;
    double fx(double dx) => (dx / w).clamp(0.0, 1.0);
    double fy(double dy) => (dy / boxH).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) =>
          _apply(h, fx(d.localPosition.dx) * 100, (1 - fy(d.localPosition.dy)) * 100),
      onPanUpdate: (d) =>
          _apply(h, fx(d.localPosition.dx) * 100, (1 - fy(d.localPosition.dy)) * 100),
      child: Stack(
        children: [
          Container(
            height: boxH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.white, hueSolid],
              ),
              border: Border.all(color: colors.outlineVariant),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: boxH,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xFF000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: (s / 100) * w - 9,
            top: (1 - v / 100) * boxH - 9,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hexColor(_hsvToHex(h, s, v)),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
                  BoxShadow(color: Color(0x99000000), blurRadius: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hueField(double w, double h, double s, double v, List<Color> hueColors,
      SereneColorScheme colors) {
    const barH = 16.0;
    double fx(double dx) => (dx / w).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _apply(fx(d.localPosition.dx) * 360, s, v),
      onPanUpdate: (d) => _apply(fx(d.localPosition.dx) * 360, s, v),
      child: Stack(
        children: [
          Container(
            height: barH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(colors: hueColors),
              border: Border.all(color: colors.outlineVariant),
            ),
          ),
          Positioned(
            left: (h / 360) * w - 10,
            top: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hexColor(_hsvToHex(h, 100, 100)),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 4),
                  BoxShadow(color: Color(0x99000000), blurRadius: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _hexInput(SereneColorScheme colors) {
    return InputDecoration(
      prefixText: '# ',
      prefixStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.onSurfaceVariant,
      ),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary),
      ),
    );
  }
}

List<double> _hexToRgb(String hex) {
  final full = hex.replaceAll('#', '');
  final cleaned = full.length == 3
      ? full.split('').map((c) => '$c$c').join()
      : full;
  final n = int.tryParse(cleaned, radix: 16) ?? 0;
  return [
    ((n >> 16) & 255).toDouble(),
    ((n >> 8) & 255).toDouble(),
    (n & 255).toDouble(),
  ];
}

List<double> _hexToHsv(String hex) {
  final rgb = _hexToRgb(hex);
  final r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255;
  final max = <double>[r, g, b].reduce(math.max);
  final min = <double>[r, g, b].reduce(math.min);
  final d = max - min;
  double h;
  if (d == 0) {
    h = 0;
  } else if (max == r) {
    h = ((g - b) / d) % 6;
  } else if (max == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  if (h < 0) h += 360;
  return [h, max == 0 ? 0 : (d / max) * 100, max * 100];
}

String _hsvToHex(double h, double s, double v) {
  h = (h % 360 + 360) % 360;
  s /= 100;
  v /= 100;
  final c = v * s;
  final x = c * (1 - (((h / 60) % 2) - 1).abs());
  final m = v - c;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c; g = x;
  } else if (h < 120) {
    r = x; g = c;
  } else if (h < 180) {
    g = c; b = x;
  } else if (h < 240) {
    g = x; b = c;
  } else if (h < 300) {
    r = x; b = c;
  } else {
    r = c; b = x;
  }
  String f(double n) => ((n + m) * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${f(r)}${f(g)}${f(b)}';
}

/// Dashed rounded rect used for the cover upload zone, matching the web's
/// `.upload-zone` dashed border.
class _ShelfDashedPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _ShelfDashedPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_ShelfDashedPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _ShelfDetailScreen extends StatefulWidget {
  final Shelf shelf;
  final List<Book> books;
  final ValueChanged<Book> onOpenBook;
  final ShelvesService service;
  const _ShelfDetailScreen({
    required this.shelf,
    required this.books,
    required this.onOpenBook,
    required this.service,
  });

  @override
  State<_ShelfDetailScreen> createState() => _ShelfDetailScreenState();
}

class _ShelfDetailScreenState extends State<_ShelfDetailScreen> {
  late List<ShelfBook> _shelfBooks = widget.shelf.books;
  late Shelf _shelf = widget.shelf;
  late final Map<String, Book> _bookById = {
    for (final b in widget.books) b.id: b,
  };
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches the full shelf — the list endpoint omits the books array, so the
  /// detail view must load it before showing anything.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await widget.service.get(widget.shelf.id);
      if (!mounted) return;
      setState(() {
        _shelf = fresh;
        _shelfBooks = fresh.books;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.service.get(widget.shelf.id);
      if (!mounted) return;
      setState(() {
        _shelf = fresh;
        _shelfBooks = fresh.books;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _edit() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShelfFormDialog(
        service: widget.service,
        books: widget.books,
        initial: _shelf,
        onSaved: (shelf) async {
          LibraryRefresh.instance.upsertShelf(shelf);
          await _reload();
        },
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${_shelf.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.service.delete(_shelf.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _manageBooks() async {
    final current = _shelfBooks.map((b) => b.id).toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _BookPickerDialog(
        books: widget.books,
        selected: current,
      ),
    );
    if (result == null || !mounted) return;

    final desired = result;
    setState(() => _loading = true);
    try {
      for (final b in widget.books) {
        final wantIn = desired.contains(b.id);
        final isIn = current.contains(b.id);
        if (wantIn && !isIn) {
          await widget.service.addBook(_shelf.id, b.id);
        } else if (!wantIn && isIn) {
          await widget.service.removeBook(_shelf.id, b.id);
        }
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update books: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeBook(ShelfBook book) async {
    setState(() => _loading = true);
    try {
      await widget.service.removeBook(_shelf.id, book.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Remove failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(_shelf.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.title.copyWith(color: colors.onSurface)),
                ),
                IconButton(
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit shelf',
                ),
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete shelf',
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    ShelfCover(shelf: _shelf, height: 170),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.errorContainer,
                          borderRadius: const BorderRadius.all(SereneShape.md),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Couldn\'t refresh this shelf.',
                                style: SereneType.labelMd.copyWith(
                                    color: colors.onErrorContainer),
                              ),
                            ),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_shelf.description != null &&
                        _shelf.description!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(_shelf.description!,
                          style: SereneType.uiBody
                              .copyWith(color: colors.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Books in this shelf (${_shelfBooks.length})',
                            style: SereneType.headlineMobile
                                .copyWith(color: colors.primary)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _manageBooks,
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_shelfBooks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No books in this shelf yet. Tap "Add" to pick from your library.',
                          textAlign: TextAlign.center,
                          style: SereneType.uiBody
                              .copyWith(color: colors.onSurfaceVariant),
                        ),
                      )
                    else
                      for (final b in _shelfBooks)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLow,
                            borderRadius: const BorderRadius.all(SereneShape.md),
                          ),
                          child: InkWell(
                            borderRadius: const BorderRadius.all(SereneShape.md),
                            onTap: () {
                              final full = _bookById[b.id];
                              if (full != null) widget.onOpenBook(full);
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    height: 56,
                                    child: BookCover(
                                      book: _bookById[b.id] ??
                                          Book(id: b.id, title: b.title),
                                      borderRadius: 6,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(b.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: SereneType.labelMd
                                                .copyWith(color: colors.onSurface)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _bookById[b.id]?.author ??
                                              (b.extractionStatus == 'failed'
                                                  ? 'Extraction failed'
                                                  : ''),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: SereneType.labelSm.copyWith(
                                              color: colors.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _removeBook(b),
                                    icon: Icon(Icons.close,
                                        size: 20, color: colors.onSurfaceVariant),
                                    tooltip: 'Remove from shelf',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                if (_loading)
                  Positioned.fill(
                    child: Container(
                      color: colors.surface.withValues(alpha: 0.4),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookPickerDialog extends StatefulWidget {
  final List<Book> books;
  final Set<String> selected;
  const _BookPickerDialog({required this.books, required this.selected});

  @override
  State<_BookPickerDialog> createState() => _BookPickerDialogState();
}

class _BookPickerDialogState extends State<_BookPickerDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return AlertDialog(
      title: const Text('Add books to shelf'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: widget.books.isEmpty
            ? Center(
                child: Text('No books uploaded yet.',
                    style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant)),
              )
            : ListView(
                children: [
                  for (final b in widget.books)
                    CheckboxListTile(
                      value: _selected.contains(b.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(b.id);
                        } else {
                          _selected.remove(b.id);
                        }
                      }),
                      title: Text(b.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(b.author ?? ''),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
