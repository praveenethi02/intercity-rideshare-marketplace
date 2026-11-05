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
  AuthService(this.baseUrl);

  final String baseUrl;
  String? _accessToken;
  String? _refreshToken;
  AppUser? user;

  late final ApiClient _public = ApiClient(baseUrl: baseUrl, tokenProvider: () async => null);

  /// Client for every other feature: adds the token and refreshes it on 401.
  late final ApiClient api = ApiClient(
    baseUrl: baseUrl,
    tokenProvider: () async => _accessToken,
    onUnauthorized: refresh,
  );

  void _saveTokens(Map<String, dynamic> tokens) {
    _accessToken = tokens['accessToken'] as String?;
    _refreshToken = tokens['refreshToken'] as String?;
  }

  Future<AppUser> login(String phone, String password) async {
    final r = await _public.post('/auth/login', {'phone': phone, 'password': password});
    final data = r.data as Map<String, dynamic>;
    _saveTokens(data['tokens'] as Map<String, dynamic>);
    return user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
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
