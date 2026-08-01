import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/books_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import '../widgets/book_cover.dart';

/// The "Reader" destination: a focused Continue Reading card for the book you
/// were last reading, matching the immersive intent of the reader tab.
class ReaderTabScreen extends StatefulWidget {
  final ValueChanged<Book> onOpenBook;
  const ReaderTabScreen({super.key, required this.onOpenBook});

  @override
  State<ReaderTabScreen> createState() => _ReaderTabScreenState();
}

class _ReaderTabScreenState extends State<ReaderTabScreen> {
  final _booksService = BooksService();
  Book? _lastBook;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final books = await _booksService.list();
      Book? best;
      double bestProgress = 0;
      for (final b in books) {
        double p = 0;
        try {
          p = await _booksService.progress(b.id);
        } catch (_) {}
        if (p > bestProgress) {
          bestProgress = p;
          best = b.copyWith(progress: p);
        }
      }
      if (!mounted) return;
      setState(() {
        _lastBook = best;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lastBook == null
                    ? _EmptyReader(onBrowse: () {})
                    : _ContinueCard(book: _lastBook!, onContinue: widget.onOpenBook),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Book book;
  final ValueChanged<Book> onContinue;
  const _ContinueCard({required this.book, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final progress = (book.progress ?? 0).clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Continue Reading',
          style: SereneType.headlineMobile.copyWith(color: colors.primary),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: SereneShape.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: BookCover(book: book, progress: book.progress),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.title.copyWith(color: colors.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author ?? '',
                      style:
                          SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('${(progress * 100).round()}%',
                            style: SereneType.labelSm
                                .copyWith(color: colors.onSurfaceVariant)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: SereneShape.fullPill,
                            child: Container(
                              height: 8,
                              color: colors.outlineVariant,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: Container(color: colors.primary),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => onContinue(book),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Continue Reading'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyReader extends StatelessWidget {
  final VoidCallback onBrowse;
  const _EmptyReader({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 56, color: colors.outlineVariant),
            const SizedBox(height: 16),
            Text('Nothing to read yet',
                style: SereneType.title.copyWith(color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Open a book from your library to begin.',
              textAlign: TextAlign.center,
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
