import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/serene_tokens.dart';
import 'stable_network_image.dart';

/// 2:3 book cover. If a real cover image is present it is shown full-bleed;
/// otherwise a calm placeholder (icon + "PDF Document") keeps the shelf
/// feeling designed rather than empty. A thick teal progress bar hugs the
/// bottom edge when the reader has made progress.
class BookCover extends StatelessWidget {
  final Book book;
  final double? progress;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool showProgress;

  const BookCover({
    super.key,
    required this.book,
    this.progress,
    this.borderRadius = 16,
    this.onTap,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decode covers at display resolution instead of their full
          // upload size, so a 300x450px shelf card doesn't hold a multi-MB
          // bitmap in memory.
          final rawW =
              constraints.maxWidth * MediaQuery.devicePixelRatioOf(context);
          final cacheWidth =
              rawW.isFinite && rawW > 0 ? rawW.round() : null;
          final coverUrl = book.coverUrl;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                _coverImage(cacheWidth, coverUrl, scheme)
              else
                _placeholder(scheme),
              const DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0x14FFFFFF)),
                  ),
                ),
              ),
              if (showProgress && progress != null && progress! > 0)
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
          );
        },
      ),
    );

    if (onTap == null) return cover;
    return GestureDetector(onTap: onTap, child: cover);
  }

  Widget _coverImage(int? cacheWidth, String url, ColorScheme scheme) {
    final provider = StableNetworkImage(url);
    return Image(
      image: cacheWidth != null
          ? ResizeImage(provider, width: cacheWidth)
          : provider,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(scheme),
    );
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerLow,
        child: LayoutBuilder(
          builder: (context, c) {
            // The "Recently Added" row shows tiny covers, so shrink the icon and
            // drop the text label rather than overflowing the 2:3 box.
            final compact = c.maxHeight < 80;
            final iconSize = compact ? 22.0 : 40.0;
            final label = compact
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'PDF Document',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SereneType.labelMd
                          .copyWith(color: scheme.outlineVariant),
                    ),
                  );
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.menu_book, size: iconSize, color: scheme.outlineVariant),
                if (!compact) const SizedBox(height: 8),
                label,
              ],
            );
          },
        ),
      );
}
