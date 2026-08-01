import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/books_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import '../widgets/book_card.dart';
import '../widgets/book_cover.dart';

/// The Cloud Library: "Recently Read" horizontal carousel + "My Shelves"
/// adaptive grid, topped by the AnyShelf brand bar and a cloud-sync FAB.
class LibraryScreen extends StatefulWidget {
  final ValueChanged<Book> onOpenBook;
  const LibraryScreen({super.key, required this.onOpenBook});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _booksService = BooksService();
  List<Book> _books = [];
  bool _loading = true;
  String? _error;

  List<Book> get _recentlyRead =>
      _books.where((b) => (b.progress ?? 0) > 0).toList()
        ..sort((a, b) => (b.progress ?? 0).compareTo(a.progress ?? 0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final books = await _booksService.list();
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final isTablet = MediaQuery.sizeOf(context).width >= SereneLayout.tabletBreakpoint;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: SereneShape.xl),
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

    final recently = _recentlyRead;
    final columns = _columnCount(MediaQuery.sizeOf(context).width);

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: 24)),
          if (recently.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionLabel('Recently Read'),
            ),
            SliverToBoxAdapter(
              child: _RecentlyReadRow(books: recently, onOpen: widget.onOpenBook),
            ),
            const SliverPadding(padding: EdgeInsets.only(top: 40)),
          ],
          SliverToBoxAdapter(
            child: _SectionLabel(
              'My Shelves',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.grid_view, color: colors.primary, size: 22),
                    tooltip: 'Grid view',
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.view_list,
                        color: colors.onSurfaceVariant, size: 22),
                    tooltip: 'List view',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 32,
                crossAxisSpacing: 16,
                childAspectRatio: 2 / 3 + 0.34,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => BookCard(
                  book: _books[index],
                  progress: _books[index].progress,
                  onTap: () => widget.onOpenBook(_books[index]),
                ),
                childCount: _books.length,
              ),
            ),
          ),
          if (_books.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyLibrary(),
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

  void _showAddSheet(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to your library',
                style: SereneType.headlineMobile.copyWith(color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Upload a PDF from your device, Google Drive, Dropbox, or a URL.',
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.upload_file, color: colors.primary),
              title: const Text('Upload PDF'),
              subtitle: const Text('From this device'),
              shape: RoundedRectangleBorder(borderRadius: SereneShape.md),
              onTap: () => _notYet(context),
            ),
            ListTile(
              leading: Icon(Icons.link, color: colors.primary),
              title: const Text('Import from URL'),
              subtitle: const Text('Fetch a PDF from a link'),
              shape: RoundedRectangleBorder(borderRadius: SereneShape.md),
              onTap: () => _notYet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _notYet(BuildContext context) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upload is coming soon.')),
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

class _RecentlyReadRow extends StatelessWidget {
  final List<Book> books;
  final ValueChanged<Book> onOpen;
  const _RecentlyReadRow({required this.books, required this.onOpen});

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
                        BookCover(book: book, progress: book.progress),
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories, size: 56, color: colors.outlineVariant),
            const SizedBox(height: 16),
            Text('Your library is empty',
                style: SereneType.title.copyWith(color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Upload your first PDF to start your cloud library.',
              textAlign: TextAlign.center,
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
