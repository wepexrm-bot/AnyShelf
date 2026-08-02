import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import '../services/books_service.dart';
import '../services/library_refresh.dart';
import '../services/shelves_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import '../widgets/book_card.dart';
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
  final _shelvesService = ShelvesService();
  List<Book> _books = [];
  List<Shelf> _shelves = [];
  bool _loading = true;
  String? _error;

  String _query = '';
  String _genre = '';
  _BooksSort _sort = _BooksSort.newest;

  @override
  void initState() {
    super.initState();
    _load();
    LibraryRefresh.instance.addListener(_load);
  }

  @override
  void dispose() {
    LibraryRefresh.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _booksService.list(),
        _shelvesService.list(),
      ]);
      final books = results[0] as List<Book>;
      _shelves = results[1] as List<Shelf>;
      final progress = <String, double>{};
      await Future.wait(books.map((b) async {
        try {
          progress[b.id] = await _booksService.progress(b.id);
        } catch (_) {}
      }));
      if (!mounted) return;
      setState(() {
        _books = [
          for (final b in books)
            b.copyWith(progress: progress[b.id] ?? b.progress),
        ];
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

  List<Book> get _filtered {
    final q = _query.trim().toLowerCase();
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final filtered = _books.where((b) {
      final haystack =
          '${b.title} ${b.author ?? ''} ${b.genre ?? ''}'.toLowerCase();
      if (!tokens.every(haystack.contains)) return false;
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

  bool get _hasActiveFilters => _query.isNotEmpty || _genre.isNotEmpty;

  Future<void> _editBook(Book book) async {
    final meta = await showDialog<_EditMeta>(
      context: context,
      builder: (_) => _EditBookDialog(book: book),
    );
    if (meta == null || !mounted) return;
    try {
      await _booksService.update(
        book.id,
        title: meta.title,
        author: meta.author,
        genre: meta.genre,
      );
      LibraryRefresh.instance.bump();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Book updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  Future<void> _moveToShelf(Book book) async {
    final shelf = await showDialog<Shelf>(
      context: context,
      builder: (context) => _ShelfPickerDialog(shelves: _shelves),
    );
    if (shelf == null || !mounted) return;
    try {
      await _shelvesService.addBook(shelf.id, book.id);
      LibraryRefresh.instance.bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to "${shelf.name}"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not move to shelf: $e')),
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
    try {
      await _booksService.api.delete('/books/${book.id}');
      LibraryRefresh.instance.bump();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
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
        onPressed: () => UploadFlow.showAddSheet(context, onUploaded: () async {
          LibraryRefresh.instance.bump();
          await _load();
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
    if (_error != null) {
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
              FilledButton(onPressed: _load, child: const Text('Retry')),
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
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildToolbar(context)),
          const SliverPadding(padding: EdgeInsets.only(top: 20)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Row(
                children: [
                  Text('Books',
                      style: SereneType.headlineMobile.copyWith(color: colors.onSurface)),
                  const Spacer(),
                  Text(
                    '${filtered.length} ${filtered.length == 1 ? 'book' : 'books'}',
                    style: SereneType.labelMd.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_books.isEmpty ? Icons.auto_stories : Icons.search_off,
                          size: 56, color: colors.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        _books.isEmpty ? 'No books yet' : 'No matching books',
                        style: SereneType.title.copyWith(color: colors.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _books.isEmpty
                            ? 'Upload a PDF to get started.'
                            : 'Try a different search or filter.',
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
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search your library…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _query = ''),
                    ),
            ),
          ),
          const SizedBox(height: 12),
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
                    _query = '';
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
  const _EditMeta({required this.title, required this.author, this.genre});
}

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

  @override
  void dispose() {
    _titleCtl.dispose();
    _authorCtl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtl.text.trim().isNotEmpty && _authorCtl.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_EditMeta(
      title: _titleCtl.text.trim(),
      author: _authorCtl.text.trim(),
      genre: _genre.isEmpty ? null : _genre,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit book info'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtl,
              decoration: const InputDecoration(labelText: 'Book name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorCtl,
              decoration: const InputDecoration(labelText: 'Author'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _genre,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Genre'),
              items: [
                const DropdownMenuItem(value: '', child: Text('No genre')),
                for (final g in BooksService.genres)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _genre = v ?? ''),
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
          onPressed: _valid ? _submit : null,
          child: const Text('Save'),
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
