import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/serene_tokens.dart';

/// 2:3 book cover. If a real cover image is present it is shown full-bleed;
/// otherwise a calm placeholder (icon + "PDF Document") keeps the shelf
/// feeling designed rather than empty. A thick teal progress bar hugs the
/// bottom edge when the reader has made progress.
class BookCover extends StatelessWidget {
  final Book book;
  final double? progress;
  final double borderRadius;
  final VoidCallback? onTap;

  const BookCover({
    super.key,
    required this.book,
    this.progress,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (book.coverUrl != null && book.coverUrl!.isNotEmpty)
            Image.network(
              book.coverUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(scheme),
            )
          else
            _placeholder(scheme),
          const DecoratedBox(
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
          ),
          if (progress != null && progress! > 0)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 6,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress!.clamp(0.0, 1.0),
                  child: Container(color: const Color(0xFF134E4A)),
                ),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return cover;
    return GestureDetector(onTap: onTap, child: cover);
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerLow,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, size: 40, color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'PDF Document',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SereneType.labelMd.copyWith(color: scheme.outlineVariant),
              ),
            ),
          ],
        ),
      );
}
