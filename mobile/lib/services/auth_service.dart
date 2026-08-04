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

  Future<bool> hasSession() async =>
      (await api.getToken())?.isNotEmpty ?? false;

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
