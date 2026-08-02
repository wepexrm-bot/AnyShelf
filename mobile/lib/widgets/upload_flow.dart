import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/books_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// Shared "Add to your library" flow used by the Library and Books screens:
/// an upload action sheet, device PDF picker, metadata form and progress
/// dialog. Everything routes through [BooksService.upload].
class UploadFlow {
  const UploadFlow._();

  static Future<void> showAddSheet(
    BuildContext context, {
    required Future<void> Function() onUploaded,
  }) async {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    // The sheet's builder context is disposed as soon as it pops, so the
    // picker/upload flow must run on the caller's context, which stays mounted.
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to your library',
                style: SereneType.headlineMobile.copyWith(color: colors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Upload a PDF from your device, Google Drive, Dropbox, or a URL.',
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.upload_file, color: colors.primary),
              title: const Text('Upload PDF'),
              subtitle: const Text('From this device'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.md)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _pickAndUpload(context, onUploaded);
              },
            ),
            ListTile(
              leading: Icon(Icons.link, color: colors.primary),
              title: const Text('Import from URL'),
              subtitle: const Text('Fetch a PDF from a link'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.md)),
              onTap: () {
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Upload is coming soon.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _pickAndUpload(
    BuildContext context,
    Future<void> Function() onUploaded,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    if (!context.mounted) return;

    final meta = await showDialog<_UploadMeta>(
      context: context,
      builder: (_) => _UploadFormDialog(defaultTitle: _baseName(file.name)),
    );
    if (meta == null || !context.mounted) return;

    await _performUpload(context, file, meta, onUploaded);
  }

  static Future<void> _performUpload(
    BuildContext context,
    XFile file,
    _UploadMeta meta,
    Future<void> Function() onUploaded,
  ) async {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _UploadingDialog(),
      ),
    );
    try {
      final bytes = await file.readAsBytes();
      await BooksService().upload(
        filename: file.name,
        bytes: bytes,
        title: meta.title,
        author: meta.author,
        genre: meta.genre,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload queued — extracting pages…')),
      );
      await onUploaded();
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  static String _baseName(String name) {
    final n = name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return n.trim().isEmpty ? 'Untitled' : n.trim();
  }
}

class _UploadMeta {
  final String title;
  final String author;
  final String? genre;
  const _UploadMeta({required this.title, required this.author, this.genre});
}

class _UploadFormDialog extends StatefulWidget {
  final String defaultTitle;
  const _UploadFormDialog({required this.defaultTitle});

  @override
  State<_UploadFormDialog> createState() => _UploadFormDialogState();
}

class _UploadFormDialogState extends State<_UploadFormDialog> {
  late final TextEditingController _titleCtl =
      TextEditingController(text: widget.defaultTitle);
  final _authorCtl = TextEditingController();
  String _genre = '';

  @override
  void dispose() {
    _titleCtl.dispose();
    _authorCtl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtl.text.trim().isNotEmpty && _authorCtl.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_UploadMeta(
      title: _titleCtl.text.trim(),
      author: _authorCtl.text.trim(),
      genre: _genre.isEmpty ? null : _genre,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return AlertDialog(
      title: const Text('Upload PDF'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Give your book a name, author and genre.',
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtl,
              decoration: const InputDecoration(labelText: 'Book name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _authorCtl,
              decoration: const InputDecoration(labelText: 'Author'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Genre'),
              items: [
                const DropdownMenuItem(value: '', child: Text('No genre')),
                for (final g in BooksService.genres)
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: (v) => setState(() => _genre = v ?? ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}

class _UploadingDialog extends StatelessWidget {
  const _UploadingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Uploading…')),
        ],
      ),
    );
  }
}
