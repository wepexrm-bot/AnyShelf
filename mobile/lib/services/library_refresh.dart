import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import 'books_service.dart';
import 'shelves_service.dart';

/// Global "library changed" signal and shared cache. Any mutation (upload,
/// delete, move to shelf, shelf edits) calls [bump]; every data screen —
/// Library, Books, Shelves — reads the refreshed snapshot from this one
/// fetch. Previously each screen fetched the same books + per-book progress +
/// shelves in parallel on every [bump], triplicating the network load.
class LibraryRefresh extends ChangeNotifier {
  LibraryRefresh._();

  static final LibraryRefresh instance = LibraryRefresh._();

  List<Book>? _books;
  List<Shelf>? _shelves;
  Map<String, double>? _progress;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _dirty = false;
  Object? _error;

  List<Shelf>? get shelves => _shelves;
  bool get isLoading => _loading;

  /// True once at least one load attempt has completed (success or failure),
  /// so screens can distinguish "still loading" from "failed to load".
  bool get hasLoaded => _loadedOnce;

  Object? get error => _error;

  /// Books with per-book reading progress merged in.
  List<Book> books() {
    final base = _books ?? const <Book>[];
    final progress = _progress;
    if (progress == null) return base;
    return [
      for (final b in base) b.copyWith(progress: progress[b.id] ?? b.progress),
    ];
  }

  /// Refreshes the shared snapshot. Overlapping calls coalesce into one fetch
  /// so screens joining mid-load don't each re-download the library.
  Future<void> reload() async {
    if (_loading) return;
    _loading = true;
    try {
      final booksService = BooksService();
      final shelvesService = ShelvesService();
      final books = await booksService.list();
      final progress = <String, double>{};
      await Future.wait(books.map((b) async {
        try {
          progress[b.id] = await booksService.progress(b.id);
        } catch (_) {}
      }));
      final shelves = await shelvesService.list();
      _books = books;
      _shelves = shelves;
      _progress = progress;
      _error = null;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _loadedOnce = true;
      notifyListeners();
      // A mutation bumped while the fetch was in flight; re-run once it
      // settles so the change isn't hidden by the stale snapshot.
      if (_dirty) {
        _dirty = false;
        reload();
      }
    }
  }

  /// Signals a library mutation (upload, delete, shelf edit...). Triggers a
  /// reload, or queues one if a fetch is already in flight.
  void bump() {
    if (_loading) {
      _dirty = true;
      return;
    }
    reload();
  }
}
