import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the app keeps between launches. The access token stays in memory only.
class SavedSession {
  final String? baseUrl;
  final String? refreshToken;
  const SavedSession({this.baseUrl, this.refreshToken});
}

abstract class SessionStore {
  Future<SavedSession> read();
  Future<void> save({required String baseUrl, required String refreshToken});

  /// Forgets the refresh token and keeps the API address.
  Future<void> clearToken();
}

/// Keeps the session in the Android Keystore or iOS Keychain.
///
/// A storage failure never stops the app. The user just has to sign in again next time.
class SecureSessionStore implements SessionStore {
  const SecureSessionStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _baseUrlKey = 'api_base_url';
  static const _refreshTokenKey = 'refresh_token';

  @override
  Future<SavedSession> read() async {
    try {
      return SavedSession(
        baseUrl: await _storage.read(key: _baseUrlKey),
        refreshToken: await _storage.read(key: _refreshTokenKey),
      );
    } catch (e) {
      debugPrint('Could not read the saved session: ${e.runtimeType}');
      return const SavedSession();
    }
  }

  @override
  Future<void> save({required String baseUrl, required String refreshToken}) async {
    try {
      await _storage.write(key: _baseUrlKey, value: baseUrl);
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    } catch (e) {
      debugPrint('Could not save the session: ${e.runtimeType}');
    }
  }

  @override
  Future<void> clearToken() async {
    try {
      await _storage.delete(key: _refreshTokenKey);
    } catch (e) {
      debugPrint('Could not clear the session: ${e.runtimeType}');
    }
  }
}

/// Keeps the session only while the app runs. Used by tests and by default in [AuthService].
class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.baseUrl, this.refreshToken});

  String? baseUrl;
  String? refreshToken;

  @override
  Future<SavedSession> read() async => SavedSession(baseUrl: baseUrl, refreshToken: refreshToken);

  @override
  Future<void> save({required String baseUrl, required String refreshToken}) async {
    this.baseUrl = baseUrl;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearToken() async => refreshToken = null;
}
