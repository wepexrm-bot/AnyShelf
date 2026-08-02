import 'dart:async';
import 'dart:typed_data';

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
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: SereneShape.sheetTop,
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
              tileColor: colors.surfaceContainerLow,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.lg)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _pickAndUpload(context, onUploaded);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.link, color: colors.primary),
              title: const Text('Import from URL'),
              subtitle: const Text('Fetch a PDF from a link'),
              tileColor: colors.surfaceContainerLow,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(SereneShape.lg)),
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
    final file = await _pickPdf();
    if (file == null) return;
    if (!context.mounted) return;

    final meta = await showDialog<_UploadMeta>(
      context: context,
      builder: (_) => _UploadFormDialog(initialFile: file),
    );
    if (meta == null || !context.mounted) return;

    await _performUpload(context, meta.file, meta, onUploaded);
  }

  static Future<XFile?> _pickPdf() async {
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
    );
    return openFile(acceptedTypeGroups: [typeGroup]);
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
        coverBytes: meta.coverBytes,
        coverName: meta.coverName,
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
  final XFile file;
  final String title;
  final String author;
  final String? genre;
  final Uint8List? coverBytes;
  final String? coverName;
  const _UploadMeta({
    required this.file,
    required this.title,
    required this.author,
    this.genre,
    this.coverBytes,
    this.coverName,
  });
}

class _UploadFormDialog extends StatefulWidget {
  final XFile initialFile;
  const _UploadFormDialog({required this.initialFile});

  @override
  State<_UploadFormDialog> createState() => _UploadFormDialogState();
}

class _UploadFormDialogState extends State<_UploadFormDialog> {
  late XFile _file = widget.initialFile;
  late final TextEditingController _titleCtl =
      TextEditingController(text: UploadFlow._baseName(_file.name));
  final _authorCtl = TextEditingController();
  String _genre = '';
  Uint8List? _coverBytes;
  String? _coverName;

  SereneColorScheme get _colors =>
      Theme.of(context).extension<SereneTheme>()!.colors;

  @override
  void dispose() {
    _titleCtl.dispose();
    _authorCtl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleCtl.text.trim().isNotEmpty && _authorCtl.text.trim().isNotEmpty;

  Future<void> _changePdf() async {
    final picked = await UploadFlow._pickPdf();
    if (picked == null || !mounted) return;
    setState(() {
      _file = picked;
      if (_titleCtl.text.trim().isEmpty) {
        _titleCtl.text = UploadFlow._baseName(picked.name);
      }
    });
  }

  Future<void> _pickCover() async {
    const typeGroup = XTypeGroup(
      label: 'Image',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _coverBytes = bytes;
      _coverName = file.name;
    });
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(_UploadMeta(
      file: _file,
      title: _titleCtl.text.trim(),
      author: _authorCtl.text.trim(),
      genre: _genre.isEmpty ? null : _genre,
      coverBytes: _coverBytes,
      coverName: _coverName,
    ));
  }

  InputDecoration _input(String hint) {
    final colors = _colors;
    return InputDecoration(
      hintText: hint,
      hintStyle: SereneType.uiBody.copyWith(fontSize: 14, color: colors.outline),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: _inputBorder(),
      enabledBorder: _inputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary),
      ),
    );
  }

  OutlineInputBorder _inputBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _colors.outlineVariant),
      );

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Dialog(
      backgroundColor: colors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(colors),
              const SizedBox(height: 20),
              _pdfField(colors),
              const SizedBox(height: 20),
              _label(colors, 'Book name', required: true),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtl,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                decoration: _input('e.g. The Great Gatsby'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Author', required: true),
              const SizedBox(height: 6),
              TextField(
                controller: _authorCtl,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                decoration: _input('e.g. F. Scott Fitzgerald'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Genre'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _genre,
                isExpanded: true,
                style: SereneType.uiBody
                    .copyWith(fontSize: 14, color: colors.onSurface),
                dropdownColor: colors.surfaceContainerLow,
                menuMaxHeight: 360,
                decoration: _input('Select a genre (optional)'),
                icon: Icon(Icons.expand_more, color: colors.onSurfaceVariant),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Select a genre (optional)'),
                  ),
                  for (final g in BooksService.genres)
                    DropdownMenuItem(value: g, child: Text(g)),
                ],
                onChanged: (v) => setState(() => _genre = v ?? ''),
              ),
              const SizedBox(height: 20),
              _label(colors, 'Cover image', optional: true),
              const SizedBox(height: 6),
              _coverZone(colors),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: SereneType.labelMd
                            .copyWith(color: colors.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _valid ? _submit : null,
                    icon: const Icon(Icons.upload_file, size: 17),
                    label: const Text('Upload'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(SereneColorScheme colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.upload_file,
                    size: 22, color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text(
                'Upload PDF',
                style: SereneType.title.copyWith(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Give your book a name, author and genre — many PDFs come '
                'with unclear filenames.',
                style: SereneType.labelMd.copyWith(
                  fontSize: 13,
                  color: colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, size: 20, color: colors.onSurfaceVariant),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _label(
    SereneColorScheme colors,
    String text, {
    bool required = false,
    bool optional = false,
  }) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: SereneType.labelSm.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.04,
            color: colors.onSurfaceVariant,
          ),
        ),
        if (required)
          Text(' *',
              style: SereneType.labelSm.copyWith(color: colors.error)),
        if (optional)
          Text('  OPTIONAL',
              style: SereneType.labelSm.copyWith(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              )),
      ],
    );
  }

  Widget _pdfField(SereneColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(colors, 'PDF file', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf, size: 22, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SereneType.labelMd.copyWith(color: colors.onSurface),
                ),
              ),
              TextButton(
                onPressed: _changePdf,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coverZone(SereneColorScheme colors) {
    final hasCover = _coverBytes != null;
    return GestureDetector(
      onTap: _pickCover,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 132,
          color: colors.surfaceContainerLow,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _DashedRectPainter(
                  color: colors.outlineVariant,
                  radius: 18,
                ),
              ),
              if (hasCover)
                Image.memory(_coverBytes!, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        size: 26, color: colors.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Upload a cover image',
                      style: SereneType.labelMd.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'JPG or PNG, optional',
                      style: SereneType.labelSm.copyWith(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded rectangle used for the PDF/cover upload zones, matching the
/// web's `.upload-zone` dashed border.
class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    const dash = 8.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _UploadingDialog extends StatelessWidget {
  const _UploadingDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Dialog(
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(borderRadius: SereneShape.card),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                'Uploading…',
                style: SereneType.labelMd.copyWith(color: colors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
