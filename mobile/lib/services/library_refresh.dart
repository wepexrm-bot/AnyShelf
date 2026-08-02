import 'package:flutter/foundation.dart';

/// Global "library changed" signal. Any mutation (upload, delete, move to
/// shelf, shelf edits) calls [bump] so every data screen — Library, Books,
/// Shelves — reloads, since they are kept alive together in the shell.
class LibraryRefresh extends ChangeNotifier {
  LibraryRefresh._();

  static final LibraryRefresh instance = LibraryRefresh._();

  void bump() => notifyListeners();
}
