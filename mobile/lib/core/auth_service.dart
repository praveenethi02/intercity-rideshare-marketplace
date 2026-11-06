import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'session_store.dart';

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

/// Signs in with Member 1's auth API. The access token stays in memory and the refresh token is
/// saved in [SessionStore], so the user stays signed in when the app restarts.
class AuthService {
  AuthService(this.baseUrl, {http.Client? httpClient, SessionStore? store})
      : _httpClient = httpClient,
        _store = store ?? MemorySessionStore();

  final String baseUrl;
  final http.Client? _httpClient;
  final SessionStore _store;
  String? _accessToken;
  String? _refreshToken;
  Future<void>? _refreshing;
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

  Future<void> _saveTokens(Map<String, dynamic> tokens) async {
    final refreshToken = tokens['refreshToken'] as String;
    _accessToken = tokens['accessToken'] as String?;
    _refreshToken = refreshToken;
    await _store.save(baseUrl: baseUrl, refreshToken: refreshToken);
  }

  Future<void> _forgetTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _store.clearToken();
  }

  Future<AppUser> _signIn(ApiResponse response) async {
    final data = response.data as Map<String, dynamic>;
    await _saveTokens(data['tokens'] as Map<String, dynamic>);
    return user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<AppUser> login(String phone, String password) async =>
      _signIn(await _public.post('/auth/login', {'phone': phone, 'password': password}));

  /// Signs in again with a saved refresh token when the app starts. Throws [ApiException] if that
  /// fails. A temporary failure keeps the saved token so the user can try again.
  Future<AppUser> restore(String refreshToken) async {
    _refreshToken = refreshToken;
    await _refreshTokens();
    try {
      final r = await api.get('/users/me');
      return user = AppUser.fromJson((r.data as Map<String, dynamic>)['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (!e.isTemporary) await _forgetTokens();
      rethrow;
    }
  }

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
    try {
      await _refreshTokens();
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Each refresh token works once, and the backend ends the session if one is used twice.
  /// So requests that get 401 at the same time share one refresh.
  Future<void> _refreshTokens() => _refreshing ??= _sendRefresh().whenComplete(() => _refreshing = null);

  Future<void> _sendRefresh() async {
    final token = _refreshToken;
    if (token == null) throw const ApiException(401, 'Please sign in again.');
    try {
      final r = await _public.post('/auth/refresh', {'refreshToken': token});
      // The user may have signed out while this was running.
      if (_refreshToken != token) return;
      await _saveTokens((r.data as Map<String, dynamic>)['tokens'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (!e.isTemporary && _refreshToken == token) await _forgetTokens();
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Signing out locally is enough if the server cannot be reached.
    }
    await _forgetTokens();
    user = null;
  }
}
