import 'package:flutter/material.dart';

import '../models/annotation.dart';
import '../models/book.dart';
import '../services/books_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';

/// The Notes destination: every highlight and sticky note across your
/// library, grouped by book.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _booksService = BooksService();
  Map<String, List<Annotation>> _grouped = {};
  Map<String, String> _titles = {};
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
      final titles = {for (final b in books) b.id: b.title};
      final grouped = await _booksService.allAnnotations();
      if (!mounted) return;
      setState(() {
        _grouped = grouped;
        _titles = titles;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _grouped.isEmpty
                    ? const _EmptyNotes()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                          children: [
                            for (final entry in _grouped.entries) ...[
                              Text(
                                _titles[entry.key] ?? 'Unknown',
                                style: SereneType.headlineMobile
                                    .copyWith(color: Theme.of(context)
                                        .extension<SereneTheme>()!
                                        .colors
                                        .primary),
                              ),
                              const SizedBox(height: 12),
                              for (final a in entry.value)
                                _NoteTile(annotation: a),
                              const SizedBox(height: 28),
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Annotation annotation;
  const _NoteTile({required this.annotation});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final highlightColor = annotation.color != null
        ? Color(int.parse('FF${annotation.color!.replaceAll('#', '')}', radix: 16))
        : const Color(0xFFFEF08A);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: SereneShape.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: highlightColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                annotation.isNote ? 'Note' : 'Highlight',
                style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
          if (annotation.anchor != null && annotation.anchor!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '“${annotation.anchor}”',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: SereneType.readingBody.copyWith(
                fontSize: 16,
                height: 1.5,
                color: colors.onSurface,
              ),
            ),
          ],
          if (annotation.noteText != null && annotation.noteText!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              annotation.noteText!,
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 56, color: colors.outlineVariant),
            const SizedBox(height: 16),
            Text('No notes yet',
                style: SereneType.title.copyWith(color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Highlights and notes you make while reading appear here.',
              textAlign: TextAlign.center,
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
