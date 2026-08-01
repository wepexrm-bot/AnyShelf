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

  Future<dynamic> get(String path) =>
      _send('GET', path, headers: await _headers());

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path,
      body: body == null ? null : jsonEncode(body), headers: await _headers());

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path,
      body: body == null ? null : jsonEncode(body), headers: await _headers());

  Future<dynamic> delete(String path, {Object? body}) => _send('DELETE', path,
      body: body == null ? null : jsonEncode(body), headers: await _headers());

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers);
      case 'PUT':
        res = await http.put(uri, headers: headers, body: body);
      case 'DELETE':
        res = await http.delete(uri, headers: headers, body: body);
      default:
        res = await http.post(uri, headers: headers, body: body);
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
