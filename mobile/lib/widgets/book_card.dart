import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/serene_tokens.dart';
import 'book_cover.dart';

/// A shelf book card: 2:3 cover, then title (2-line clamp) + author in the
/// app chrome faces, with a "more" menu on the cover when any action is wired
/// up (edit / move to shelf / delete).
class BookCard extends StatelessWidget {
  final Book book;
  final double? progress;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onMoveToShelf;
  final VoidCallback? onDelete;

  const BookCard({
    super.key,
    required this.book,
    this.progress,
    this.onTap,
    this.onEdit,
    this.onMoveToShelf,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMenu = onEdit != null || onMoveToShelf != null || onDelete != null;
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: BookCover(book: book, progress: progress, onTap: onTap),
                    ),
                  ),
                ),
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
        ),
        if (hasMenu)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: PopupMenuButton<String>(
                tooltip: 'More options',
                color: scheme.surfaceContainer,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                icon: const Icon(Icons.more_vert,
                    color: Colors.white, size: 20),
                padding: const EdgeInsets.all(6),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit?.call();
                    case 'move':
                      onMoveToShelf?.call();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (context) => [
                  if (onEdit != null)
                    const PopupMenuItem(
                        value: 'edit', child: Text('Edit book info')),
                  if (onMoveToShelf != null)
                    const PopupMenuItem(
                        value: 'move', child: Text('Move to shelf')),
                  if (onDelete != null)
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
