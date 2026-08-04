import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Compares the installed build against the latest GitHub release and reports
/// whether a forced update is required.
class UpdateService {
  static const String owner = 'wepexrm-bot';
  static const String repo = 'AnyShelf';
  static const String _releasesUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';
  static const String _releasesPage =
      'https://github.com/$owner/$repo/releases/latest';

  /// Returns the latest release tag (e.g. `v5.0.9`) when it is newer than the
  /// installed version, otherwise null. Any failure also returns null so a
  /// network blip or rate limit never locks the user out.
  static Future<String?> requiredUpdateTag() async {
    try {
      final res = await http
          .get(Uri.parse(_releasesUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String?;
      if (tag == null || tag.isEmpty) return null;
      final info = await PackageInfo.fromPlatform();
      final latest = _versionOf(tag);
      final installed = _versionOf(info.version);
      return _isNewer(latest, installed) ? tag : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> openReleasesPage() async {
    await launchUrl(Uri.parse(_releasesPage));
  }

  /// Parses a version/tag like `v5.0.8` into [major, minor, patch].
  static List<int> _versionOf(String value) {
    final cleaned = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final parts = cleaned.split('.');
    return [
      for (var i = 0; i < 3; i++) int.tryParse(parts.length > i ? parts[i] : '') ?? 0,
    ];
  }

  static bool _isNewer(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}
