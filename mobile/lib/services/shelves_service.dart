import '../models/shelf.dart';
import 'api_client.dart';

/// Shelves CRUD against the backend.
class ShelvesService {
  final ApiClient api;
  ShelvesService({ApiClient? api}) : api = api ?? ApiClient();

  Future<List<Shelf>> list() async {
    final data = await api.get('/shelves/');
    final items = data as List;
    return items.map((s) => _reachable(Shelf.fromJson(s as Map<String, dynamic>))).toList();
  }

  Future<Shelf> get(String id) async {
    final data = await api.get('/shelves/$id');
    return _reachable(Shelf.fromJson(data as Map<String, dynamic>));
  }

  Future<Shelf> create({
    required String name,
    String? description,
    String? color,
    bool isPublic = false,
  }) async {
    final data = await api.post('/shelves/', body: {
      'name': name,
      'description': description,
      'is_public': isPublic,
      'color': color,
    });
    return _reachable(Shelf.fromJson(data as Map<String, dynamic>));
  }

  Future<Shelf> update(String id,
      {String? name, String? description, String? color}) async {
    final data = await api.put('/shelves/$id', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
    });
    return _reachable(Shelf.fromJson(data as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    await api.delete('/shelves/$id');
  }

  Future<void> addBook(String shelfId, String bookId) async {
    await api.post('/shelves/$shelfId/books/$bookId');
  }

  Future<void> removeBook(String shelfId, String bookId) async {
    await api.delete('/shelves/$shelfId/books/$bookId');
  }

  Shelf _reachable(Shelf s) => Shelf(
        id: s.id,
        name: s.name,
        description: s.description,
        isPublic: s.isPublic,
        color: s.color,
        bannerUrl: api.reachableUrl(s.bannerUrl),
        bookCount: s.bookCount,
        createdAt: s.createdAt,
        bookIds: s.bookIds,
        books: s.books,
      );
}
