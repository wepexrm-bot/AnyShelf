import '../models/reader_settings.dart';
import 'api_client.dart';

class SettingsService {
  final ApiClient api;
  SettingsService({ApiClient? api}) : api = api ?? ApiClient();

  /// Loads the user's saved reading preferences from the backend.
  Future<ReaderSettings> fetch() async {
    try {
      final data = await api.get('/settings/');
      return ReaderSettings.fromApi(data as Map<String, dynamic>);
    } catch (_) {
      return ReaderSettings.defaults();
    }
  }

  /// Best-effort push of the reading preferences. Failures are swallowed so a
  /// missing network never breaks the reading experience.
  Future<void> save(ReaderSettings settings) async {
    try {
      await api.put('/settings/', body: settings.toApi());
    } catch (_) {}
  }
}
