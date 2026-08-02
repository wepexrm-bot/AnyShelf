import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ui_mode_controller.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import 'sync_indicator.dart';

/// Branded top bar: filled cloud glyph + "AnyShelf" wordmark (Playfair, accent
/// green) on the left, an optional light/dark toggle, and the trailing widget
/// (by default the cloud sync status). Reads "top app bar" in the design.
class AppHeader extends StatelessWidget {
  final Widget? trailing;
  final bool showSync;
  final bool showThemeToggle;
  final EdgeInsetsGeometry padding;
  const AppHeader({
    super.key,
    this.trailing,
    this.showSync = true,
    this.showThemeToggle = true,
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/images/logo.png', width: 28, height: 28),
          ),
          const SizedBox(width: 8),
          Text(
            'AnyShelf',
            style: SereneType.headlineMobile.copyWith(
              color: colors.accentTeal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (showThemeToggle) ...[
            Consumer<UiModeController>(
              builder: (context, uiMode, _) => IconButton(
                onPressed: uiMode.toggle,
                tooltip: uiMode.isDark ? 'Switch to light mode' : 'Switch to dark mode',
                icon: Icon(
                  uiMode.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          trailing ?? (showSync ? const SyncIndicator() : const SizedBox()),
        ],
      ),
    );
  }
}
