import 'package:flutter/material.dart';

import '../models/book.dart';
import '../screens/books_screen.dart';
import '../screens/library_screen.dart';
import '../screens/reader_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shelves_screen.dart';
import '../screens/stats_screen.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// The app shell. On phones it shows the bottom navigation with the active
/// tab rendered as a filled pill; on tablets the five destinations move to a
/// fixed side rail. Tabs match the web: Library, Books, Shelves, Stats,
/// Settings.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet =
        MediaQuery.sizeOf(context).width >= SereneLayout.tabletBreakpoint;

    final pages = [
      LibraryScreen(
        onOpenBook: _openBook,
        onGoToShelves: () => setState(() => _index = 2),
      ),
      BooksScreen(onOpenBook: _openBook),
      ShelvesScreen(onOpenBook: _openBook),
      const StatsScreen(),
      const SettingsScreen(),
    ];

    if (isTablet) {
      return Scaffold(
        body: Row(
          children: [
            _SideRail(
              index: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
            Expanded(child: IndexedStack(index: _index, children: pages)),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomNav(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

abstract final class _Destinations {
  static const _library = (Icons.home_outlined, Icons.home, 'Library');
  static const _books = (Icons.library_books_outlined, Icons.library_books, 'Books');
  static const _shelves = (Icons.collections_bookmark_outlined, Icons.collections_bookmark, 'Shelves');
  static const _stats = (Icons.leaderboard_outlined, Icons.leaderboard, 'Stats');
  static const _settings = (Icons.settings_outlined, Icons.settings, 'Settings');
}

class _BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _BottomNav({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final items = [
      _Destinations._library,
      _Destinations._books,
      _Destinations._shelves,
      _Destinations._stats,
      _Destinations._settings,
    ];
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3))),
        borderRadius: SereneShape.sheetTop,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavItem(
                  active: index == i,
                  outlinedIcon: items[i].$1,
                  filledIcon: items[i].$2,
                  label: items[i].$3,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool active;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;
  final VoidCallback onTap;
  const _NavItem({
    required this.active,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: active ? colors.primaryContainer : Colors.transparent,
        borderRadius: SereneShape.fullPill,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? filledIcon : outlinedIcon,
            size: 24,
            color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: SereneType.labelSm.copyWith(
              color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(onTap: onTap, child: content);
  }
}

class _SideRail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _SideRail({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final items = [
      _Destinations._library,
      _Destinations._books,
      _Destinations._shelves,
      _Destinations._stats,
      _Destinations._settings,
    ];
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        border: Border(right: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            for (var i = 0; i < items.length - 1; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _RailItem(
                  active: index == i,
                  outlinedIcon: items[i].$1,
                  filledIcon: items[i].$2,
                  label: items[i].$3,
                  onTap: () => onSelect(i),
                ),
              ),
            const Spacer(),
            // Settings stays pinned to the bottom of the rail.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _RailItem(
                active: index == items.length - 1,
                outlinedIcon: items.last.$1,
                filledIcon: items.last.$2,
                label: items.last.$3,
                onTap: () => onSelect(items.length - 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final bool active;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;
  final VoidCallback onTap;
  const _RailItem({
    required this.active,
    required this.outlinedIcon,
    required this.filledIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final color = active ? colors.primary : colors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? colors.primaryContainer : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? filledIcon : outlinedIcon,
              size: 24,
              color: active ? colors.onPrimaryContainer : color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: SereneType.labelSm.copyWith(
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
