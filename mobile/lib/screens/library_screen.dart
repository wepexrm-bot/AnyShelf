import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../models/book.dart';
import 'reader_screen.dart';

const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    setState(() => _loading = true);
    final res = await http.get(Uri.parse('$apiBase/books/'));
    final data = jsonDecode(res.body) as List;
    setState(() {
      _books = data.map((b) => Book.fromJson(b)).toList();
      _loading = false;
    });
  }

  // File picking would use the `file_picker` package to select a PDF from
  // device storage, then upload via a multipart POST to /books/upload --
  // omitted here to keep the scaffold dependency-light.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Library')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchBooks,
              child: ListView.builder(
                itemCount: _books.length,
                itemBuilder: (context, index) {
                  final book = _books[index];
                  return ListTile(
                    title: Text(book.title),
                    subtitle: Text(
                      '${book.extractionStatus}'
                      '${book.reflowConfidence != null ? " · reflow: ${book.reflowConfidence}" : ""}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: wire up file_picker + upload
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
