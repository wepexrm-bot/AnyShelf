import 'package:flutter/material.dart';

import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import 'sync_indicator.dart';

/// Branded top bar: filled cloud glyph + "AnyShelf" wordmark (Literata, accent
/// teal) on the left, optional trailing widget — by default the cloud sync
/// status. Reads "top app bar" in the design, fixed with a soft blur.
class AppHeader extends StatelessWidget {
  final Widget? trailing;
  final bool showSync;
  final EdgeInsetsGeometry padding;
  const AppHeader({
    super.key,
    this.trailing,
    this.showSync = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.82),
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.25))),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_done, color: colors.accentTeal, size: 26),
          const SizedBox(width: 8),
          Text(
            'AnyShelf',
            style: SereneType.headlineMobile.copyWith(
              color: colors.accentTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          trailing ?? (showSync ? const SyncIndicator() : const SizedBox()),
        ],
      ),
    );
  }
}
