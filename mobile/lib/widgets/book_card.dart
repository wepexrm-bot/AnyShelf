import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/serene_tokens.dart';
import 'book_cover.dart';

/// A shelf book card: 2:3 cover, then title (2-line clamp) + author in the
/// app chrome faces, with the sync glyph in the corner.
class BookCard extends StatelessWidget {
  final Book book;
  final double? progress;
  final VoidCallback? onTap;

  const BookCard({super.key, required this.book, this.progress, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: BookCover(book: book, progress: progress, onTap: onTap),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.labelMd.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      book.author ?? 'Unknown Author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.uiBody
                          .copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.cloud_done,
                    size: 16, color: scheme.outlineVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
