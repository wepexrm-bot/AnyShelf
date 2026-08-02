import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import '../services/books_service.dart';
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
  final _booksService = BooksService();
  List<Shelf> _shelves = [];
  List<Book> _books = [];
  bool _loading = true;

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
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _shelvesService.list(),
        _booksService.list(),
      ]);
      if (!mounted) return;
      setState(() {
        _shelves = results[0] as List<Shelf>;
        _books = results[1] as List<Book>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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
    if (changed == true) _load();
    LibraryRefresh.instance.bump();
  }

  Future<void> _createShelf() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShelfFormDialog(
        service: _shelvesService,
        onSaved: _load,
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
    return RefreshIndicator(
      onRefresh: _load,
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
  final Future<void> Function() onSaved;
  final Shelf? initial;
  const _ShelfFormDialog({required this.service, required this.onSaved, this.initial});

  @override
  State<_ShelfFormDialog> createState() => _ShelfFormDialogState();
}

class _ShelfFormDialogState extends State<_ShelfFormDialog> {
  late final TextEditingController _nameCtl =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _descCtl =
      TextEditingController(text: widget.initial?.description ?? '');
  late String _color = widget.initial?.color ?? kShelfColorPalette.first;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final shelf = widget.initial;
      if (shelf == null) {
        await widget.service.create(
          name: name,
          description: _descCtl.text.trim().isEmpty ? null : _descCtl.text.trim(),
          color: _color,
        );
      } else {
        await widget.service.update(
          shelf.id,
          name: name,
          description: _descCtl.text.trim().isEmpty ? null : _descCtl.text.trim(),
          color: _color,
        );
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the shelf: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final previewShelf = Shelf(id: '', name: _nameCtl.text.trim().isEmpty ? 'Shelf name' : _nameCtl.text.trim(), color: _color);
    return AlertDialog(
      title: Text(widget.initial == null ? 'Create New Shelf' : 'Edit Shelf'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: ShelfCover(shelf: previewShelf, height: 96),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            Text('Color',
                style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kShelfColorPalette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: shelfColorFromHex(c, fallback: colors.primary),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c
                              ? colors.primary
                              : colors.outlineVariant,
                          width: _color == c ? 3 : 1,
                        ),
                      ),
                      child: _color == c
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameCtl.text.trim().isEmpty || _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : (widget.initial == null ? 'Create' : 'Save')),
        ),
      ],
    );
  }
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Fetches the full shelf — the list endpoint omits the books array, so the
  /// detail view must load it before showing anything.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fresh = await widget.service.get(widget.shelf.id);
      if (!mounted) return;
      setState(() {
        _shelf = fresh;
        _shelfBooks = fresh.books;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.service.get(widget.shelf.id);
      if (!mounted) return;
      setState(() {
        _shelf = fresh;
        _shelfBooks = fresh.books;
      });
    } catch (_) {}
  }

  Future<void> _edit() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShelfFormDialog(
        service: widget.service,
        initial: _shelf,
        onSaved: _reload,
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
