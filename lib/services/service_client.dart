import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/server.dart';

/// A failure talking to a server, with a message fit to show the user.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Base for every service client. Handles the local/remote address switch,
/// proxy basic auth, timeouts and error messages.
///
/// When a server has both a local and a remote address, the local one is
/// tried first with a short timeout; whichever answers is remembered and
/// tried first next time, so leaving home switches over on its own.
abstract class ServiceClient {
  ServiceClient(this.server, {http.Client? httpClient})
    : httpClient = httpClient ?? http.Client();

  final ServerConfig server;
  final http.Client httpClient;
  Uri? _preferred;

  static const quickTimeout = Duration(seconds: 4);
  static const fullTimeout = Duration(seconds: 25);

  /// The address that answered last, if any.
  Uri? get activeBase => _preferred;

  /// Checks the server answers and the credentials work.
  Future<void> test();

  void close() => httpClient.close();

  /// Headers every request carries (API keys, cookies…).
  Map<String, String> authHeaders() => const {};

  Future<http.Response> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? json,
    Map<String, String>? form,
    Map<String, String>? multipart,
    Map<String, String>? headers,
    bool checkStatus = true,
  }) async {
    final bases = server.baseUris;
    if (bases.isEmpty) throw ApiException('No address set for ${server.name}.');
    final order = [
      if (_preferred != null && bases.contains(_preferred)) _preferred!,
      ...bases.where((b) => b != _preferred),
    ];

    Object? lastError;
    for (var i = 0; i < order.length; i++) {
      final base = order[i];
      final isLast = i == order.length - 1;
      try {
        final req = _build(
          method,
          base,
          path,
          query: query,
          json: json,
          form: form,
          multipart: multipart,
          headers: headers,
        );
        final streamed = await httpClient
            .send(req)
            .timeout(isLast ? fullTimeout : quickTimeout);
        final res = await http.Response.fromStream(streamed)
            .timeout(fullTimeout);
        _preferred = base;
        if (checkStatus) _check(res);
        return res;
      } on ApiException {
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    _preferred = null;
    throw ApiException(_networkMessage(lastError));
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async =>
      decode(await request('GET', path, query: query));

  Future<dynamic> sendJson(
    String method,
    String path, {
    Object? json,
    Map<String, dynamic>? query,
  }) async => decode(await request(method, path, json: json, query: query));

  static dynamic decode(http.Response res) {
    if (res.body.trim().isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(
        'The server answered, but not with data Control understands. '
        'Check the address points at the right app.',
      );
    }
  }

  http.BaseRequest _build(
    String method,
    Uri base,
    String path, {
    Map<String, dynamic>? query,
    Object? json,
    Map<String, String>? form,
    Map<String, String>? multipart,
    Map<String, String>? headers,
  }) {
    final uri = joinUri(base, path, query);
    final allHeaders = <String, String>{
      'Accept': 'application/json',
      if (server.proxyUser.isNotEmpty)
        'Authorization': basicAuth(server.proxyUser, server.proxyPassword),
      ...server.headerMap,
      ...authHeaders(),
      ...?headers,
    };
    if (multipart != null) {
      return http.MultipartRequest(method, uri)
        ..headers.addAll(allHeaders)
        ..fields.addAll(multipart);
    }
    final req = http.Request(method, uri)..headers.addAll(allHeaders);
    if (json != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(json);
    } else if (form != null) {
      req.bodyFields = form;
    }
    return req;
  }

  void _check(http.Response res) {
    final code = res.statusCode;
    if (code < 400) return;
    if (code == 401 || code == 403) {
      throw ApiException(
        '${server.name} refused the request ($code). Check the API key or login.',
        statusCode: code,
      );
    }
    if (code == 404) {
      throw ApiException(
        '${server.name} doesn\'t have that page (404). Check the address, '
        'including any URL base like /sonarr.',
        statusCode: code,
      );
    }
    var detail = '';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) detail = body['message'];
      if (body is List && body.isNotEmpty && body.first is Map) {
        detail = (body.first as Map)['errorMessage']?.toString() ?? '';
      }
    } catch (_) {}
    throw ApiException(
      '${server.name} returned an error ($code)${detail.isEmpty ? '' : ': $detail'}',
      statusCode: code,
    );
  }

  String _networkMessage(Object? e) {
    if (e is TimeoutException) {
      return '${server.name} didn\'t answer in time. Is it running, and is the address right?';
    }
    if (e is HandshakeException) {
      return 'Secure connection to ${server.name} failed. Check its HTTPS certificate.';
    }
    return 'Can\'t reach ${server.name}. Check the address and that you\'re on the right network.';
  }
}

/// Appends [path] to [base] (keeping any URL base such as /sonarr).
Uri joinUri(Uri base, String path, [Map<String, dynamic>? query]) {
  final basePath = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final p = path.startsWith('/') ? path : '/$path';
  final uri = base.replace(
    path: '$basePath$p',
    queryParameters: (query == null || query.isEmpty) ? null : query,
  );
  // Encode spaces as %20, not +: some servers (Overseerr) read + literally.
  // A real + in a value is already %2B, so every + here is a space.
  return uri.hasQuery
      ? uri.replace(query: uri.query.replaceAll('+', '%20'))
      : uri;
}

String basicAuth(String user, String password) =>
    'Basic ${base64Encode(utf8.encode('$user:$password'))}';
