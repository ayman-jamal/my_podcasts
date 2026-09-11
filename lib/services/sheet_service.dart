import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/podcast.dart';

class SheetException implements Exception {
  final String message;
  const SheetException(this.message);

  @override
  String toString() => message;
}

/// Thrown when adding a video that already exists in the sheet.
class DuplicatePodcastException extends SheetException {
  final String existingId;
  const DuplicatePodcastException(this.existingId)
      : super('This episode is already in your list.');
}

/// Client for the Google Apps Script web app (see apps_script/Code.gs).
class SheetService {
  SheetService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  Future<List<Podcast>> list(String scriptUrl, String token) async {
    final base = _parseUrl(scriptUrl);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      'action': 'list',
      'token': token,
    });
    final res = await _send(() => _client.get(uri));
    final data = _unwrap(res);
    if (data is! List) throw const SheetException('Unexpected response from sheet.');
    return data
        .whereType<Map<String, dynamic>>()
        .map(Podcast.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  Future<Podcast> add(String scriptUrl, String token, Podcast podcast) async {
    final data = await _post(scriptUrl, {
      'token': token,
      'action': 'add',
      'podcast': podcast.toJson(),
    });
    return Podcast.fromJson(data as Map<String, dynamic>);
  }

  Future<Podcast> update(String scriptUrl, String token, Podcast podcast) async {
    final data = await _post(scriptUrl, {
      'token': token,
      'action': 'update',
      'podcast': podcast.toJson(),
    });
    return Podcast.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String scriptUrl, String token, String id) async {
    await _post(scriptUrl, {'token': token, 'action': 'delete', 'id': id});
  }

  // -------------------------------------------------------------------------

  Future<Object?> _post(String scriptUrl, Map<String, dynamic> body) async {
    final uri = _parseUrl(scriptUrl);
    final res = await _send(() async {
      // Apps Script answers a POST with a 302 redirect to the actual result.
      // Follow it manually with a GET.
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode(body);
      final streamed = await _client.send(request);
      final first = await http.Response.fromStream(streamed);
      if (first.isRedirect || (first.statusCode >= 300 && first.statusCode < 400)) {
        final location = first.headers['location'];
        if (location == null) {
          throw const SheetException('Sheet redirect without location.');
        }
        return _client.get(uri.resolve(location));
      }
      return first;
    });
    return _unwrap(res);
  }

  Future<http.Response> _send(Future<http.Response> Function() fn) async {
    try {
      return await fn().timeout(_timeout);
    } on SheetException {
      rethrow;
    } catch (e) {
      throw SheetException('Network error: could not reach the sheet ($e).');
    }
  }

  Object? _unwrap(http.Response res) {
    if (res.statusCode != 200) {
      throw SheetException('Sheet request failed (HTTP ${res.statusCode}).');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const SheetException(
          'Sheet returned an unexpected page. Check the Script URL and that the '
          'web app is deployed with access "Anyone".');
    }
    if (json['ok'] == true) return json['data'];

    final error = json['error']?.toString() ?? 'Unknown error';
    if (error.startsWith('DUPLICATE:')) {
      throw DuplicatePodcastException(error.substring('DUPLICATE:'.length));
    }
    throw SheetException(error);
  }

  Uri _parseUrl(String scriptUrl) {
    final uri = Uri.tryParse(scriptUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SheetException('Invalid Script URL. Set it in Settings.');
    }
    return uri;
  }
}
