import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/book.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Color _background = Colors.white;
  Color _textColor = Colors.black;
  double _fontSize = 18;
  String _fontFamily = 'Georgia';

  void _applyPreset(Color bg, Color text) {
    setState(() {
      _background = bg;
      _textColor = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reflowAvailable = widget.book.reflowAvailable;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => _showThemeSheet(context, reflowAvailable),
          ),
        ],
      ),
      body: Container(
        color: _background,
        child: reflowAvailable
            ? _buildReflowView()
            // Fixed-layout fallback: renders the original PDF as-is for
            // scanned or low-confidence-extraction books. Only the
            // surrounding background theme changes, not the page content.
            : SfPdfViewer.network(
                'PDF_PRESIGNED_URL_HERE', // supply from book detail endpoint
              ),
      ),
    );
  }

  Widget _buildReflowView() {
    // In a full implementation, this renders the structured JSON
    // (paragraphs/headings) fetched from the backend, styled with
    // _fontFamily / _fontSize / _textColor -- the mobile equivalent of
    // ReflowView.jsx on web.
    return Center(
      child: Text(
        'Reflowed text renders here, styled per user theme.',
        style: TextStyle(fontSize: _fontSize, fontFamily: _fontFamily, color: _textColor),
      ),
    );
  }

  void _showThemeSheet(BuildContext context, bool reflowAvailable) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _themeSwatch('Light', Colors.white, Colors.black),
                _themeSwatch('Sepia', const Color(0xFFF4ECD8), const Color(0xFF3B3324)),
                _themeSwatch('Night', const Color(0xFF1B1B1F), const Color(0xFFE8E8E8)),
              ],
            ),
            if (!reflowAvailable)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Font controls need reflow mode, which isn\'t available for this book.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _themeSwatch(String label, Color bg, Color text) {
    return GestureDetector(
      onTap: () {
        _applyPreset(bg, text);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          CircleAvatar(backgroundColor: bg, child: Icon(Icons.circle, color: text, size: 12)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
