import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One field error returned by the backend validator.
class FieldError {
  final String field;
  final String message;
  const FieldError(this.field, this.message);
}

/// Thrown for every failed request. [statusCode] is 0 when the server
/// could not be reached at all.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final List<FieldError> fieldErrors;

  /// Error code from meta.code, e.g. DRIVER_NOT_VERIFIED, TRIP_LOCKED.
  final String? code;

  const ApiException(this.statusCode, this.message, [this.fieldErrors = const [], this.code]);

  bool get isNetworkError => statusCode == 0;

  @override
  String toString() {
    if (fieldErrors.isEmpty) return message;
    return '$message: ${fieldErrors.map((e) => '${e.field} ${e.message}').join(', ')}';
  }
}

/// The team envelope: { success, message, data, meta }.
class ApiResponse {
  final dynamic data;
  final Map<String, dynamic> meta;
  final String message;
  const ApiResponse({this.data, this.meta = const {}, this.message = ''});
}

/// Small HTTP client shared by all features. [AuthService] gives it the
/// access token and refreshes it when it expires.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    this.onUnauthorized,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// e.g. http://10.0.2.2:4000/api/v1 (Android emulator -> your PC)
  final String baseUrl;
  final Future<String?> Function() tokenProvider;

  /// Called once when a request gets 401. Return true after refreshing the
  /// token to retry the request (access tokens last 15 minutes).
  final Future<bool> Function()? onUnauthorized;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Future<ApiResponse> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<ApiResponse> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<ApiResponse> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<ApiResponse> delete(String path) => _send('DELETE', path);

  Future<ApiResponse> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    var res = await _rawSend(method, path, body: body, query: query);
    final refresh = onUnauthorized;
    if (res.statusCode == 401 && refresh != null && !path.startsWith('/auth/') && await refresh()) {
      res = await _rawSend(method, path, body: body, query: query);
    }
    return _parse(res);
  }

  Future<http.Response> _rawSend(String method, String path, {Object? body, Map<String, String>? query}) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);

    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    try {
      final streamed = await _http.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'The server did not respond. Check your connection.');
    } catch (_) {
      throw ApiException(0, 'Cannot reach the server at $baseUrl');
    }
  }

  ApiResponse _parse(http.Response res) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(res.statusCode, 'Unexpected server response (${res.statusCode})');
    }

    final meta = (json['meta'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    if (json['success'] != true) {
      // details is a list of field errors for validation, or an object for some errors.
      final rawDetails = meta['details'];
      final details = rawDetails is List ? rawDetails : const [];
      throw ApiException(
        res.statusCode,
        (json['message'] as String?) ?? 'Request failed',
        details
            .whereType<Map<String, dynamic>>()
            .map((d) => FieldError('${d['field']}', '${d['message']}'))
            .toList(),
        meta['code'] as String?,
      );
    }
    return ApiResponse(data: json['data'], meta: meta, message: (json['message'] as String?) ?? '');
  }
}
