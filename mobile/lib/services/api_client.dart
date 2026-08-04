import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Thin HTTP wrapper around the AnyShelf backend.
///
/// The base URL is configurable at build time:
///   flutter run --dart-define=API_BASE=http://192.168.1.20:8000
/// On the Android emulator the host machine is reachable at 10.0.2.2.
class ApiClient {
  static const String defaultBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  final String baseUrl;
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? defaultBase;

  static const Duration _timeout = Duration(seconds: 90);

  static String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'Request timed out. Check your connection and try again.';
    }
    if (error is http.ClientException) {
      return 'Network error. Check your connection and try again.';
    }
    return 'Something went wrong. Check your connection and try again.';
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove('auth_token');
    } else {
      await prefs.setString('auth_token', token);
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Rewrites `localhost`/`127.0.0.1` in storage URLs to the host of
  /// [baseUrl]. The Android emulator reaches the host machine via 10.0.2.2,
  /// so presigned MinIO URLs that point at the host's localhost otherwise
  /// resolve to the emulator itself and fail to load.
  String? reachableUrl(String? url) {
    if (url == null || url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.host != 'localhost' && uri.host != '127.0.0.1') return url;
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return url;
    return uri.replace(host: base.host, port: uri.port).toString();
  }

  Future<dynamic> get(String path) async =>
      _send('GET', path, headers: await _headers());

  Future<dynamic> post(String path, {Object? body}) async => _send('POST', path,
      body: body == null ? null : jsonEncode(body), headers: await _headers());

  Future<dynamic> put(String path, {Object? body}) async => _send('PUT', path,
      body: body == null ? null : jsonEncode(body), headers: await _headers());

  Future<dynamic> delete(String path, {Object? body}) async => _send(
        'DELETE',
        path,
        body: body == null ? null : jsonEncode(body),
        headers: await _headers(),
      );

  /// Multipart POST for file uploads (e.g. `POST /books/upload`). Attaches the
  /// bearer token and decodes/throws like the other calls.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.MultipartRequest('POST', uri);
    req.fields.addAll(fields);
    req.files.addAll(files);
    req.headers['Accept'] = 'application/json';
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    final http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(_timeout);
    } catch (e) {
      throw ApiException(0, _friendlyError(e));
    }
    final res = await http.Response.fromStream(streamed).timeout(_timeout);

    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body;
      }
    }
    if (res.statusCode >= 400) {
      var detail = decoded is Map ? decoded['detail'] : decoded;
      if (detail is String && detail.isNotEmpty) {
        throw ApiException(res.statusCode, detail);
      }
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode})');
    }
    return decoded;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(_timeout);
        case 'PUT':
          res = await http.put(uri, headers: headers, body: body).timeout(_timeout);
        case 'DELETE':
          res = await http.delete(uri, headers: headers, body: body).timeout(_timeout);
        default:
          res = await http.post(uri, headers: headers, body: body).timeout(_timeout);
      }
    } catch (e) {
      throw ApiException(0, _friendlyError(e));
    }

    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body;
      }
    }

    if (res.statusCode >= 400) {
      var detail = decoded is Map ? decoded['detail'] : decoded;
      if (detail is String && detail.isNotEmpty) {
        throw ApiException(res.statusCode, detail);
      }
      throw ApiException(res.statusCode, 'Request failed (${res.statusCode})');
    }
    return decoded;
  }
}
