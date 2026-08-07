import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/shelf.dart';
import 'books_service.dart';
import 'shelves_service.dart';

/// Global "library changed" signal and shared cache. Any mutation (upload,
/// delete, move to shelf, shelf edits) calls [bump]; every data screen —
/// Library, Books, Shelves — reads the refreshed snapshot from this one
/// fetch. Previously each screen fetched the same books + per-book progress +
/// shelves in parallel on every [bump], triplicating the network load.
///
/// The store is also the offline cache and the source of truth for optimistic
/// UI:
///
///  * [hydrate] restores the last snapshot from device storage so the first
///    frame after launch shows the library instead of an empty state.
///  * Mutations like [deleteBook] / [updateBookMeta] / [moveBookToShelf]
///    apply locally and notify immediately, then sync to the server and roll
///    back if the call fails — every screen updates in place, no full re-fetch.
///  * [reload] pulls books + a single batch progress call + shelves, then
///    re-persists the cache.
class LibraryRefresh extends ChangeNotifier {
  LibraryRefresh._();

  static final LibraryRefresh instance = LibraryRefresh._();

  static const String _cacheKey = 'library_cache_v1';

  List<Book>? _books;
  List<Shelf>? _shelves;
  Map<String, double>? _progress;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _dirty = false;
  bool _hydrated = false;
  Object? _error;
  Timer? _cacheTimer;

  List<Shelf>? get shelves => _shelves;
  bool get isLoading => _loading;

  /// True once a snapshot is available to render — either loaded from the
  /// server or restored from the offline cache. Screens use this to show a
  /// spinner instead of a premature "empty library".
  bool get hasData => _books != null;

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

  /// Restores the last-known library snapshot from device storage. Safe to
  /// call multiple times; the first call wins. Does not fetch anything — pair
  /// it with [reload] for stale-while-revalidate behaviour.
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final books = (data['books'] as List?) ?? const [];
      final shelves = (data['shelves'] as List?) ?? const [];
      final progress = (data['progress'] as Map?) ?? const {};
      _books = [
        for (final b in books.whereType<Map<String, dynamic>>())
          Book.fromCacheJson(b),
      ];
      _shelves = [
        for (final s in shelves.whereType<Map<String, dynamic>>())
          Shelf.fromCacheJson(s),
      ];
      _progress = {
        for (final e in progress.entries)
          e.key as String: (e.value as num).toDouble(),
      };
    } catch (_) {
      // Corrupt or stale cache: ignore it and fall through to a network load.
    }
    notifyListeners();
  }

  /// Refreshes the shared snapshot. Overlapping calls coalesce into one fetch
  /// so screens joining mid-load don't each re-download the library. Progress
  /// uses a single batch call rather than one request per book.
  Future<void> reload() async {
    if (_loading) return;
    _loading = true;
    try {
      final booksService = BooksService();
      final shelvesService = ShelvesService();
      // Fire both fetches together, but give each an error handler up front so
      // a failure in one can never orphan as an unhandled exception while the
      // other is still being awaited.
      Object? booksError;
      Object? shelvesError;
      final booksFuture = booksService.list().then<List<Book>?>(
        (v) => v,
        onError: (Object e, StackTrace _) {
          booksError = e;
          return null;
        },
      );
      final shelvesFuture = shelvesService.list().then<List<Shelf>?>(
        (v) => v,
        onError: (Object e, StackTrace _) {
          shelvesError = e;
          return null;
        },
      );
      final books = await booksFuture;
      Map<String, double> progress;
      if (books == null) {
        progress = <String, double>{};
      } else {
        try {
          progress = await booksService.allProgress();
        } catch (_) {
          // Batch endpoint unavailable (older server): fall back to per-book.
          progress = <String, double>{};
          for (final b in books) {
            try {
              progress[b.id] = await booksService.progress(b.id);
            } catch (_) {}
          }
        }
      }
      final shelves = await shelvesFuture;
      // Apply whatever succeeded; a failing endpoint keeps the previous
      // snapshot (e.g. the cached shelves) instead of wiping it empty.
      if (books != null) _books = books;
      if (shelves != null) _shelves = shelves;
      _progress = progress;
      _error = booksError ?? shelvesError;
      if (booksError == null && shelvesError == null) {
        _writeCache();
      }
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

  /// Drops all in-memory state (used on logout so the next user starts clean
  /// and isn't served a previous user's cached library).
  void clear() {
    _cacheTimer?.cancel();
    _books = null;
    _shelves = null;
    _progress = null;
    _loading = false;
    _loadedOnce = false;
    _dirty = false;
    _hydrated = false;
    _error = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Optimistic mutations. Each applies to the in-memory snapshot and notifies
  // immediately, then syncs to the server; on failure the snapshot is rolled
  // back so the UI never shows state the server rejected.
  // ---------------------------------------------------------------------------

  /// Removes a book (and its shelf memberships) instantly, then deletes it on
  /// the server. Returns true when the server accepted the delete.
  Future<bool> deleteBook(Book book) async {
    if (_books == null) return false;
    final index = _books!.indexWhere((b) => b.id == book.id);
    if (index < 0) return false;
    final oldBooks = List<Book>.of(_books!);
    final oldShelves = _shelves;
    _books!.removeAt(index);
    if (_shelves != null) {
      _shelves = [
        for (final s in _shelves!)
          if (s.bookIds.contains(book.id))
            Shelf(
              id: s.id,
              name: s.name,
              description: s.description,
              isPublic: s.isPublic,
              color: s.color,
              bannerUrl: s.bannerUrl,
              bookCount: (s.bookCount - 1).clamp(0, 1 << 31),
              createdAt: s.createdAt,
              bookIds: s.bookIds.where((id) => id != book.id).toList(),
              books: s.books.where((b) => b.id != book.id).toList(),
            )
          else
            s,
      ];
    }
    notifyListeners();
    try {
      await BooksService().api.delete('/books/${book.id}');
      _writeCache();
      return true;
    } catch (_) {
      _books = oldBooks;
      _shelves = oldShelves;
      notifyListeners();
      return false;
    }
  }

  /// Patches a book's title / author / genre in place, then syncs the edit.
  /// Pass `author`/`genre` as `null` to leave them untouched.
  Future<bool> updateBookMeta(
    String id, {
    String? title,
    String? author,
    String? genre,
  }) async {
    final list = _books;
    if (list == null) return false;
    final index = list.indexWhere((b) => b.id == id);
    if (index < 0) return false;
    final old = list[index];
    list[index] = Book(
      id: old.id,
      title: title ?? old.title,
      author: (author == null || author.isEmpty) ? old.author : author,
      genre: (genre == null || genre.isEmpty) ? old.genre : genre,
      coverUrl: old.coverUrl,
      pdfUrl: old.pdfUrl,
      structuredTextUrl: old.structuredTextUrl,
      extractionStatus: old.extractionStatus,
      reflowConfidence: old.reflowConfidence,
      isScanned: old.isScanned,
      progress: old.progress,
      createdAt: old.createdAt,
    );
    notifyListeners();
    try {
      await BooksService().update(
        id,
        title: title ?? old.title,
        author: (author == null || author.isEmpty) ? old.author : author,
        genre: genre,
      );
      _writeCache();
      return true;
    } catch (_) {
      list[index] = old;
      notifyListeners();
      return false;
    }
  }

  /// Replaces a book's cover URL locally (call after the cover upload
  /// succeeded and returned its URL).
  void applyCover(String bookId, String coverUrl) {
    final list = _books;
    if (list == null) return;
    final index = list.indexWhere((b) => b.id == bookId);
    if (index < 0) return;
    final old = list[index];
    list[index] = Book(
      id: old.id,
      title: old.title,
      author: old.author,
      genre: old.genre,
      coverUrl: coverUrl,
      pdfUrl: old.pdfUrl,
      structuredTextUrl: old.structuredTextUrl,
      extractionStatus: old.extractionStatus,
      reflowConfidence: old.reflowConfidence,
      isScanned: old.isScanned,
      progress: old.progress,
      createdAt: old.createdAt,
    );
    notifyListeners();
    _writeCache();
  }

  /// Prepends a freshly uploaded book to the library.
  void insertBook(Book book) {
    _books ??= [];
    _books!.removeWhere((b) => b.id == book.id);
    _books!.insert(0, book);
    notifyListeners();
    _writeCache();
  }

  /// Adds or removes a book on a shelf in place, then syncs. Rolls the shelf
  /// membership back if the server call fails. Returns true on success.
  Future<bool> moveBookToShelf(
    String shelfId,
    String bookId, {
    required bool add,
  }) async {
    final shelves = _shelves;
    if (shelves == null) return false;
    final index = shelves.indexWhere((s) => s.id == shelfId);
    if (index < 0) return false;
    final old = shelves[index];
    final ids = [...old.bookIds];
    final changed = add
        ? (ids.contains(bookId) ? ids : [...ids, bookId])
        : ids.where((id) => id != bookId).toList();
    final count = add
        ? (old.bookCount + 1).clamp(0, 1 << 31)
        : (old.bookCount - 1).clamp(0, 1 << 31);
    shelves[index] = Shelf(
      id: old.id,
      name: old.name,
      description: old.description,
      isPublic: old.isPublic,
      color: old.color,
      bannerUrl: old.bannerUrl,
      bookCount: count,
      createdAt: old.createdAt,
      bookIds: changed,
      books: old.books,
    );
    notifyListeners();
    try {
      final service = ShelvesService();
      if (add) {
        await service.addBook(shelfId, bookId);
      } else {
        await service.removeBook(shelfId, bookId);
      }
      _writeCache();
      return true;
    } catch (_) {
      shelves[index] = old;
      notifyListeners();
      return false;
    }
  }

  /// Inserts or replaces a shelf in the snapshot (used after create/edit
  /// succeeded server-side and returned the canonical shelf).
  void upsertShelf(Shelf shelf) {
    _shelves ??= [];
    final index = _shelves!.indexWhere((s) => s.id == shelf.id);
    if (index < 0) {
      _shelves!.insert(0, shelf);
    } else {
      _shelves![index] = shelf;
    }
    notifyListeners();
    _writeCache();
  }

  /// Removes a shelf instantly, then deletes it server-side, rolling back on
  /// failure. Returns true on success.
  Future<bool> deleteShelf(Shelf shelf) async {
    if (_shelves == null) return false;
    final index = _shelves!.indexWhere((s) => s.id == shelf.id);
    if (index < 0) return false;
    final old = _shelves![index];
    _shelves!.removeAt(index);
    notifyListeners();
    try {
      await ShelvesService().delete(shelf.id);
      _writeCache();
      return true;
    } catch (_) {
      _shelves!.insert(index, old);
      notifyListeners();
      return false;
    }
  }

  /// Updates a single book's progress in place so "Continue Reading" moves
  /// as the reader saves, without waiting for a reload.
  void applyProgress(String bookId, double fraction) {
    _progress ??= {};
    _progress![bookId] = fraction;
    notifyListeners();
    _writeCache();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Persists the current snapshot, debounced so bursts of mutations coalesce
  /// into a single write.
  void _writeCache() {
    _cacheTimer?.cancel();
    _cacheTimer = Timer(const Duration(milliseconds: 400), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({
        'books': [
          for (final b in _books ?? const <Book>[]) b.toCacheJson(),
        ],
        'shelves': [
          for (final s in _shelves ?? const <Shelf>[]) s.toCacheJson(),
        ],
        'progress': {
          for (final e in (_progress ?? const <String, double>{}).entries)
            e.key: e.value,
        },
        'saved_at': DateTime.now().toIso8601String(),
      }));
    });
  }
}
