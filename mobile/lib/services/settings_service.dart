import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';
import 'api_client.dart';

class SettingsService {
  final ApiClient api;
  SettingsService({ApiClient? api}) : api = api ?? ApiClient();

  /// Loads the user's saved reading preferences from the backend, then applies
  /// the locally-persisted page fit mode (not part of the backend contract).
  Future<ReaderSettings> fetch() async {
    ReaderSettings settings;
    try {
      final data = await api.get('/settings/');
      settings = ReaderSettings.fromApi(data as Map<String, dynamic>);
    } catch (_) {
      settings = ReaderSettings.defaults();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final fit = prefs.getString('reader_fit_mode');
      if (fit != null && fit.isNotEmpty) {
        settings = settings.copyWith(fitMode: FitMode.fromApi(fit));
      }
    } catch (_) {}
    return settings;
  }

  /// Best-effort push of the reading preferences. Failures are swallowed so a
  /// missing network never breaks the reading experience.
  Future<void> save(ReaderSettings settings) async {
    try {
      await api.put('/settings/', body: settings.toApi());
    } catch (_) {}
  }
}
