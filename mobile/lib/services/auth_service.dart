import 'dart:convert';

import 'api_client.dart';

class AuthService {
  final ApiClient api;
  AuthService({ApiClient? api}) : api = api ?? ApiClient();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await api.post('/auth/login',
        body: {'email': email, 'password': password});
    final map = data as Map<String, dynamic>;
    await api.setToken(map['access_token'] as String?);
    return map;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final data = await api.post('/auth/register', body: {
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me() async {
    final data = await api.get('/auth/me');
    return data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await api.setToken(null);
  }

  /// A session only counts if a token is stored *and* it hasn't expired. The
  /// backend issues JWT access tokens with a fixed lifetime, so a stale token
  /// lingering in storage must not boot the user into the library.
  Future<bool> hasSession() async {
    final token = await api.getToken();
    if (token == null || token.isEmpty) return false;
    final exp = _jwtExpiry(token);
    if (exp == null) return true; // non-JWT token: fall back to presence
    if (exp.isAfter(DateTime.now().toUtc())) return true;
    await api.setToken(null);
    return false;
  }

  /// Reads the JWT `exp` claim without verifying the signature — the timestamp
  /// lives in the base64 payload segment, so it's safe to parse locally.
  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      }
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (exp * 1000).round(),
          isUtc: true,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final data = await api
        .post('/auth/forgot-password', body: {'email': email});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    final data = await api.post('/auth/reset-password', body: {
      'email': email,
      'token': token,
      'password': password,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final data = await api
        .post('/auth/verify-email', body: {'email': email, 'code': code});
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resendVerification(String email) async {
    final data = await api.post('/auth/resend-verification', body: {'email': email});
    return data as Map<String, dynamic>;
  }
}
