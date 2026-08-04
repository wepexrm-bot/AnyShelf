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
import '../widgets/upload_flow.dart';

/// The Library (home) destination — mirrors the web home page: a "Continue
/// Reading" carousel, a "My Shelves" grid, then a "Recently Added" list.
class LibraryScreen extends StatefulWidget {
  final ValueChanged<Book> onOpenBook;
  final VoidCallback onGoToShelves;
  const LibraryScreen({
    super.key,
    required this.onOpenBook,
    required this.onGoToShelves,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _booksService = BooksService();
  final _shelvesService = ShelvesService();
  List<Book> _books = [];
  List<Shelf> _shelves = [];
  bool _loading = true;
  int _loadEpoch = 0;

  static const double _completedFraction = 0.995;

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
    final epoch = ++_loadEpoch;
    setState(() => _loading = true);
    try {
      final books = await _booksService.list();
      final progress = <String, double>{};
      await Future.wait(books.map((b) async {
        try {
          progress[b.id] = await _booksService.progress(b.id);
        } catch (_) {}
      }));
      final shelves = await _shelvesService.list();
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _books = [
          for (final b in books)
            b.copyWith(progress: progress[b.id] ?? b.progress),
        ];
        _shelves = shelves;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() => _loading = false);
    }
  }

  bool _isCompleted(Book b) => (b.progress ?? 0) >= _completedFraction;

  List<Book> get _continueReading {
    final inProgress = _books
        .where((b) => !_isCompleted(b) && (b.progress ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.progress ?? 0).compareTo(a.progress ?? 0));
    if (inProgress.isNotEmpty) return inProgress;
    return _books.where((b) => !_isCompleted(b)).toList();
  }

  List<Book> get _recentlyAdded {
    final list = [..._books]
      ..sort((a, b) =>
          (b.createdAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));
    return list.take(3).toList();
  }

  Future<void> _deleteBook(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${book.title}"?'),
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
      await _booksService.api.delete('/books/${book.id}');
      LibraryRefresh.instance.bump();
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

    final continuing = _continueReading;
    final recent = _recentlyAdded;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (continuing.isNotEmpty) ...[
            const SliverPadding(padding: EdgeInsets.only(top: 24)),
            SliverToBoxAdapter(
              child: _SectionLabel('Continue Reading'),
            ),
            SliverToBoxAdapter(
              child: _ContinueReadingRow(
                books: continuing,
                onOpen: widget.onOpenBook,
              ),
            ),
          ],
          if (_shelves.isNotEmpty) ...[
            const SliverPadding(padding: EdgeInsets.only(top: 40)),
            SliverToBoxAdapter(
              child: _SectionLabel(
                'My Shelves',
                trailing: TextButton(
                  onPressed: widget.onGoToShelves,
                  child: const Text('See all'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.15,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final shelf = _shelves[index];
                    return GestureDetector(
                      onTap: widget.onGoToShelves,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ShelfCover(
                                shelf: shelf, height: double.infinity),
                          ),
                          const SizedBox(height: 8),
                          Text(shelf.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SereneType.labelMd
                                  .copyWith(color: colors.onSurface)),
                        ],
                      ),
                    );
                  },
                  childCount: _shelves.length,
                ),
              ),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(top: 40)),
          SliverToBoxAdapter(
            child: _SectionLabel('Recently Added'),
          ),
          if (recent.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_stories,
                        size: 56, color: colors.outlineVariant),
                    const SizedBox(height: 16),
                    Text('Your library is empty',
                        style: SereneType.title.copyWith(color: colors.onSurface)),
                    const SizedBox(height: 8),
                    Text(
                      'Upload a PDF to get started.',
                      textAlign: TextAlign.center,
                      style: SereneType.uiBody
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _RecentlyAddedTile(
                    book: recent[index],
                    onTap: () => widget.onOpenBook(recent[index]),
                    onDelete: () => _deleteBook(recent[index]),
                  ),
                  childCount: recent.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: SereneType.headlineMobile.copyWith(color: colors.primary),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ContinueReadingRow extends StatelessWidget {
  final List<Book> books;
  final ValueChanged<Book> onOpen;
  const _ContinueReadingRow({required this.books, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 24),
        itemBuilder: (context, index) {
          final book = books[index];
          return SizedBox(
            width: 224,
            child: GestureDetector(
              onTap: () => onOpen(book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCover(
                            book: book,
                            progress: book.progress,
                            showProgress: false),
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(Icons.play_arrow,
                                color: colors.onPrimary, size: 26),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SereneType.labelMd.copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author ?? 'Unknown Author',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  _ProgressBar(progress: book.progress),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slim progress bar shown under a Continue Reading card's title/author.
class _ProgressBar extends StatelessWidget {
  final double? progress;
  const _ProgressBar({this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final p = (progress ?? 0).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: p,
              child: Container(color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentlyAddedTile extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _RecentlyAddedTile({
    required this.book,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final progress = (book.progress ?? 0).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 64,
              child: BookCover(book: book, progress: book.progress, borderRadius: 8),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.labelMd.copyWith(color: colors.onSurface)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        book.extractionStatus == 'failed'
                            ? 'Extraction failed'
                            : '${(progress * 100).round()}%',
                        style: SereneType.labelSm
                            .copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: SereneShape.fullPill,
                          child: Container(
                            height: 6,
                            color: colors.surfaceVariant,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: ColoredBox(color: colors.primary),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: colors.onSurfaceVariant,
              tooltip: 'Delete book',
            ),
          ],
        ),
      ),
    );
  }
}
