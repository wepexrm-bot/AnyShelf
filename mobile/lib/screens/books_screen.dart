import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import '../services/books_service.dart';
import '../services/library_refresh.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import '../widgets/book_card.dart';
import '../widgets/stable_network_image.dart';
import '../widgets/upload_flow.dart';

enum _BooksSort { newest, oldest }

/// The Books destination: every book in the library as a cover grid with
/// search, genre filter and sort — mirroring the web Books page.
class BooksScreen extends StatefulWidget {
  final ValueChanged<Book> onOpenBook;
  const BooksScreen({super.key, required this.onOpenBook});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  final _booksService = BooksService();
  List<Book> _books = [];
  List<Shelf> _shelves = [];
  bool _loading = true;
  String? _error;

  String _genre = '';
  _BooksSort _sort = _BooksSort.newest;

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

  /// Copies the shared library snapshot (books + progress + shelves) into this
  /// screen's local state. Safe to call during initState.
  void _syncFromStore() {
    final store = LibraryRefresh.instance;
    _books = store.books();
    _shelves = store.shelves ?? const [];
    _error = store.error?.toString();
    // Only spin while there is nothing at all to render yet (no cached or
    // fetched snapshot).
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

  List<Book> get _filtered {
    final filtered = _books.where((b) {
      if (_genre.isNotEmpty && b.genre != _genre) return false;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return _sort == _BooksSort.oldest ? ta.compareTo(tb) : tb.compareTo(ta);
    });
    return filtered;
  }

  bool get _hasActiveFilters => _genre.isNotEmpty;

  Future<void> _editBook(Book book) async {
    final meta = await showDialog<_EditMeta>(
      context: context,
      builder: (_) => _EditBookDialog(book: book),
    );
    if (meta == null || !mounted) return;
    // Optimistic: title/author/genre patch in place immediately, then sync.
    final ok = await LibraryRefresh.instance.updateBookMeta(
      book.id,
      title: meta.title,
      author: meta.author,
      genre: meta.genre,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update failed')),
      );
      return;
    }
    if (meta.coverBytes != null && meta.coverName != null && mounted) {
      try {
        // The cover PUT returns the new cover URL; apply it in place.
        final coverUrl = await _booksService.updateCover(
          book.id,
          coverBytes: meta.coverBytes!,
          coverName: meta.coverName!,
        );
        if (coverUrl.isNotEmpty && mounted) {
          LibraryRefresh.instance.applyCover(book.id, coverUrl);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cover update failed: $e')),
        );
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Book updated')),
    );
  }

  Future<void> _moveToShelf(Book book) async {
    final shelf = await showDialog<Shelf>(
      context: context,
      builder: (context) => _ShelfPickerDialog(shelves: _shelves),
    );
    if (shelf == null || !mounted) return;
    // Optimistic: membership toggles in place; rolled back on failure.
    final ok = await LibraryRefresh.instance
        .moveBookToShelf(shelf.id, book.id, add: true);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "${shelf.name}"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not move to shelf')),
      );
    }
  }

  Future<void> _deleteBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${book.title}"?'),
        content: const Text('This removes the book from your library. This cannot be undone.'),
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
    if (confirmed != true || !mounted) return;
    // Optimistic: the book disappears immediately; rolled back on failure.
    final ok = await LibraryRefresh.instance.deleteBook(book);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final isTablet =
        MediaQuery.sizeOf(context).width >= SereneLayout.tabletBreakpoint;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => UploadFlow.showAddSheet(context, onUploaded: (book) async {
          // Optimistic insert: the book shows up immediately; a background
          // reload reconciles cover / extraction status.
          LibraryRefresh.instance.insertBook(book);
          LibraryRefresh.instance.bump();
        }),
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
    if (_error != null && _books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              const Text('Couldn\'t reach your library'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final columns = _columnCount(screenWidth);
    final tileWidth = (screenWidth - 48 - (columns - 1) * 16) / columns;
    final tileHeight = tileWidth * 3 / 2 + 92;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildToolbar(context)),
          const SliverPadding(padding: EdgeInsets.only(top: 20)),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_books.isEmpty ? Icons.auto_stories : Icons.filter_alt_off,
                          size: 56, color: colors.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        _books.isEmpty ? 'No books yet' : 'No books in this genre',
                        style: SereneType.title.copyWith(color: colors.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _books.isEmpty
                            ? 'Upload a PDF to get started.'
                            : 'Try a different genre.',
                        textAlign: TextAlign.center,
                        style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 32,
                  crossAxisSpacing: 16,
                  childAspectRatio: tileWidth / tileHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => BookCard(
                    book: filtered[index],
                    progress: filtered[index].progress,
                    onTap: () => widget.onOpenBook(filtered[index]),
                    onEdit: () => _editBook(filtered[index]),
                    onMoveToShelf: () => _moveToShelf(filtered[index]),
                    onDelete: () => _deleteBook(filtered[index]),
                  ),
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _columnCount(double width) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  Widget _buildToolbar(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _FilterChip(
                icon: Icons.category_outlined,
                label: _genre.isEmpty ? 'All genres' : _genre,
                onTap: _genreDropdown,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.sort,
                label: _sort == _BooksSort.newest ? 'Newest' : 'Oldest',
                onTap: _sortMenu,
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    _genre = '';
                    _sort = _BooksSort.newest;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: const BorderRadius.all(SereneShape.full),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 18, color: colors.primary),
                        const SizedBox(width: 6),
                        Text('Clear', style: SereneType.labelMd.copyWith(color: colors.onSurface)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _genreDropdown() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          _GenreOption(
            label: 'All genres',
            value: '',
            selected: _genre.isEmpty,
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final g in BooksService.genres)
            _GenreOption(
              label: g,
              value: g,
              selected: _genre == g,
              onTap: () => Navigator.pop(context, g),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (selected != null) setState(() => _genre = selected);
  }

  Future<void> _sortMenu() async {
    final selected = await showModalBottomSheet<_BooksSort>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in _BooksSort.values)
              ListTile(
                title: Text(s == _BooksSort.newest
                    ? 'Newest added'
                    : 'Oldest added'),
                trailing: s == _sort ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected != null) setState(() => _sort = selected);
  }
}

class _GenreOption extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _GenreOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return ListTile(
      title: Text(label, style: SereneType.uiBody.copyWith(color: colors.onSurface)),
      trailing: selected ? Icon(Icons.check, color: colors.primary) : null,
      onTap: onTap,
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _FilterChip({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: const BorderRadius.all(SereneShape.full),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Text(label, style: SereneType.labelMd.copyWith(color: colors.onSurface)),
          ],
        ),
      ),
    );
  }
}

class _EditMeta {
  final String title;
  final String author;
  final String? genre;
  final Uint8List? coverBytes;
  final String? coverName;
  const _EditMeta({
    required this.title,
    required this.author,
    this.genre,
    this.coverBytes,
    this.coverName,
  });
}

/// Book metadata editor, mirroring the web's Edit Book dialog: header with
/// icon + subtitle, labelled name / author / genre fields, a cover picker that
/// shows the current cover, and Cancel / Save changes actions.
class _EditBookDialog extends StatefulWidget {
  final Book book;
  const _EditBookDialog({required this.book});

  @override
  State<_EditBookDialog> createState() => _EditBookDialogState();
}

class _EditBookDialogState extends State<_EditBookDialog> {
  late final TextEditingController _titleCtl =
      TextEditingController(text: widget.book.title);
  late final TextEditingController _authorCtl =
      TextEditingController(text: widget.book.author ?? '');
  late String _genre = widget.book.genre ?? '';
  Uint8List? _coverBytes;
  String? _coverName;

  SereneColorScheme get _colors =>
      Theme.of(context).extension<SereneTheme>()!.colors;

  @override
  void dispose() {
    _titleCtl.dispose();
    _authorCtl.dispose();
    super.dispose();
  }

  // Like the web form, only the book name is required to save.
  bool get _valid => _titleCtl.text.trim().isNotEmpty;

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
      _coverBytes = bytes;
      _coverName = file.name;
    });
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_EditMeta(
      title: _titleCtl.text.trim(),
      author: _authorCtl.text.trim(),
      genre: _genre.isEmpty ? null : _genre,
      coverBytes: _coverBytes,
      coverName: _coverName,
    ));
  }

  InputDecoration _input(String hint) {
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
        borderSide: BorderSide(color: colors.primary),
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
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(colors),
              const SizedBox(height: 20),
              _label(colors, 'Book name', required: true),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtl,
                autofocus: true,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                decoration: _input('e.g. The Great Gatsby'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Author'),
              const SizedBox(height: 6),
              TextField(
                controller: _authorCtl,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                decoration: _input('e.g. F. Scott Fitzgerald'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Genre'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _genre,
                isExpanded: true,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                dropdownColor: colors.surfaceContainerLow,
                menuMaxHeight: 360,
                decoration: _input('Select a genre (optional)'),
                icon: Icon(Icons.expand_more, color: colors.onSurfaceVariant),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Select a genre (optional)'),
                  ),
                  for (final g in BooksService.genres)
                    DropdownMenuItem(value: g, child: Text(g)),
                ],
                onChanged: (v) => setState(() => _genre = v ?? ''),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Cover image', optional: true),
              const SizedBox(height: 6),
              _coverZone(colors),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: SereneType.labelMd
                            .copyWith(color: colors.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _valid ? _submit : null,
                    icon: const Icon(Icons.save_outlined, size: 17),
                    label: const Text('Save changes'),
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
                child: Icon(Icons.edit_outlined,
                    size: 22, color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                'Edit Book',
                style: SereneType.title.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Update the name, author, genre or cover.',
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
        ),
      ],
    );
  }

  Widget _label(
    SereneColorScheme colors,
    String text, {
    bool required = false,
    bool optional = false,
  }) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: SereneType.labelSm.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.04,
            color: colors.onSurfaceVariant,
          ),
        ),
        if (required)
          Text(' *',
              style: SereneType.labelSm.copyWith(color: colors.error)),
        if (optional)
          Text('  OPTIONAL',
              style: SereneType.labelSm.copyWith(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              )),
      ],
    );
  }

  Widget _coverZone(SereneColorScheme colors) {
    final hasNew = _coverBytes != null;
    final currentUrl = widget.book.coverUrl;
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
                painter: DashedRectPainter(
                  color: colors.outlineVariant,
                  radius: 18,
                ),
              ),
              if (hasNew)
                Image(
                  // Decode the picked image at display resolution.
                  image: ResizeImage(
                    MemoryImage(_coverBytes!),
                    width:
                        (132 * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                  fit: BoxFit.cover,
                )
              else if (currentUrl != null && currentUrl.isNotEmpty)
                Image(
                  image: ResizeImage(
                    StableNetworkImage(currentUrl),
                    width:
                        (132 * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverHint(colors),
                )
              else
                _coverHint(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverHint(SereneColorScheme colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 26, color: colors.primary),
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
    );
  }
}

class _ShelfPickerDialog extends StatelessWidget {
  final List<Shelf> shelves;
  const _ShelfPickerDialog({required this.shelves});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return AlertDialog(
      title: const Text('Move to shelf'),
      content: SizedBox(
        width: double.maxFinite,
        child: shelves.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No shelves yet. Create one from the Shelves tab first.',
                  style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in shelves)
                    ListTile(
                      leading: const Icon(Icons.collections_bookmark_outlined),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${s.bookCount} ${s.bookCount == 1 ? 'book' : 'books'}'),
                      onTap: () => Navigator.pop(context, s),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
