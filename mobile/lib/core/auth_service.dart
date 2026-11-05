import 'package:http/http.dart' as http;

import 'api_client.dart';

/// The signed-in user (from data.user of POST /auth/login).
class AppUser {
  final String id;
  final String fullName;
  final String phone;
  final String role; // PASSENGER | DRIVER | CARGO_CUSTOMER | ADMIN

  const AppUser({required this.id, required this.fullName, required this.phone, required this.role});

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        fullName: (j['fullName'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        role: j['role'] as String,
      );

  bool get isDriver => role == 'DRIVER';
}

/// Logs in with Member 1's auth API and keeps the tokens in memory.
/// Member 1 can later store the refresh token in secure storage.
class AuthService {
  AuthService(this.baseUrl, {http.Client? httpClient}) : _httpClient = httpClient;

  final String baseUrl;
  final http.Client? _httpClient;
  String? _accessToken;
  String? _refreshToken;
  AppUser? user;

  late final ApiClient _public = ApiClient(
    baseUrl: baseUrl,
    tokenProvider: () async => null,
    httpClient: _httpClient,
  );

  /// Client for every other feature: adds the token and refreshes it on 401.
  late final ApiClient api = ApiClient(
    baseUrl: baseUrl,
    tokenProvider: () async => _accessToken,
    onUnauthorized: refresh,
    httpClient: _httpClient,
  );

  void _saveTokens(Map<String, dynamic> tokens) {
    _accessToken = tokens['accessToken'] as String?;
    _refreshToken = tokens['refreshToken'] as String?;
  }

  AppUser _signIn(ApiResponse response) {
    final data = response.data as Map<String, dynamic>;
    _saveTokens(data['tokens'] as Map<String, dynamic>);
    return user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser> login(String phone, String password) async =>
      _signIn(await _public.post('/auth/login', {'phone': phone, 'password': password}));

  /// Creates an unverified account and texts a code to [phone]. Call [verifyOtp] next.
  Future<void> register({
    required String fullName,
    required String phone,
    String? email,
    required String password,
    required String role,
  }) async {
    await _public.post('/auth/register', {
      'fullName': fullName,
      'phone': phone,
      if (email != null) 'email': email,
      'password': password,
      'role': role,
    });
  }

  /// Confirms the registration code, which activates the account and signs the user in.
  Future<AppUser> verifyOtp(String phone, String otp) async =>
      _signIn(await _public.post('/auth/otp/verify', {'phone': phone, 'otp': otp}));

  Future<void> resendOtp(String phone) async {
    await _public.post('/auth/otp/resend', {'phone': phone});
  }

  Future<void> forgotPassword(String phone) async {
    await _public.post('/auth/password/forgot', {'phone': phone});
  }

  Future<void> resetPassword(String phone, String otp, String newPassword) async {
    await _public.post('/auth/password/reset', {'phone': phone, 'otp': otp, 'newPassword': newPassword});
  }

  /// Exchanges the refresh token for new tokens. Returns false if that fails.
  Future<bool> refresh() async {
    final token = _refreshToken;
    if (token == null) return false;
    try {
      final r = await _public.post('/auth/refresh', {'refreshToken': token});
      _saveTokens((r.data as Map<String, dynamic>)['tokens'] as Map<String, dynamic>);
      return true;
    } on ApiException {
      _accessToken = null;
      _refreshToken = null;
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Signing out locally is enough if the server cannot be reached.
    }
    _accessToken = null;
    _refreshToken = null;
    user = null;
  }
}
