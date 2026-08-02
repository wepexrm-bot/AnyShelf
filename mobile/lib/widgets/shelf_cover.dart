import 'package:flutter/material.dart';

import '../models/shelf.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

const List<String> kShelfColorPalette = [
  '#154212',
  '#2D5A27',
  '#00695C',
  '#283593',
  '#5C6BC0',
  '#8E24AA',
  '#C2185B',
  '#D84315',
  '#4E342E',
  '#546E7A',
];

Color shelfColorFromHex(String? hex, {required Color fallback}) {
  if (hex == null || hex.isEmpty) return fallback;
  final cleaned = hex.replaceAll('#', '');
  final full = cleaned.length == 3
      ? cleaned.split('').map((c) => '$c$c').join()
      : cleaned;
  final v = int.tryParse(full, radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

/// A shelf cover panel: the shelf colour (or banner image) with a name badge
/// overlaid at the bottom-left, matching the web shelf cards.
class ShelfCover extends StatelessWidget {
  final Shelf shelf;
  final double height;
  final String? nameOverride;
  const ShelfCover({super.key, required this.shelf, this.height = 96, this.nameOverride});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final base = shelfColorFromHex(shelf.color, fallback: colors.primary);
    final hasBanner = shelf.bannerUrl != null && shelf.bannerUrl!.isNotEmpty;
    final name = nameOverride ?? shelf.name;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(SereneShape.md),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
        image: hasBanner
            ? DecorationImage(image: NetworkImage(shelf.bannerUrl!), fit: BoxFit.cover)
            : null,
        gradient: hasBanner
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, base.withValues(alpha: 0.6), const Color(0xFF0D0F0D)],
              ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(SereneShape.md),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x73000000)],
          ),
        ),
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(10),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SereneType.labelMd.copyWith(
              color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
