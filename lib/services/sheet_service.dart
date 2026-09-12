import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/podcast.dart';

class SheetException implements Exception {
  final String message;

  /// True for failures that may succeed when tried again
  /// (network errors, timeouts, busy sheet, HTTP 429/5xx).
  final bool transient;

  const SheetException(this.message, {this.transient = false});

  @override
  String toString() => message;
}

/// Thrown when adding a video that already exists in the sheet.
class DuplicatePodcastException extends SheetException {
  final String existingId;
  const DuplicatePodcastException(this.existingId)
      : super('This episode is already in your list.');
}

/// Result of [SheetService.ping].
class SheetStatus {
  final int version;
  final int count;
  const SheetStatus({required this.version, required this.count});
}

/// Client for the Google Apps Script web app (see apps_script/Code.gs).
class SheetService {
  SheetService({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.retryDelay = const Duration(milliseconds: 1500),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Covers Apps Script cold start, waiting for the script lock and the redirect.
  final Duration timeout;
  final Duration retryDelay;

  static const _redeployHint =
      'Deploy → Manage deployments → Edit → Version: New version.';

  Future<List<Podcast>> list(String scriptUrl, String token) async {
    final data = await _withRetry((_) => _get(scriptUrl, token, 'list'));
    if (data is! List) throw const SheetException('Unexpected response from sheet.');
    return data
        .whereType<Map<String, dynamic>>()
        .map(Podcast.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// Checks URL, token and sheet in one call.
  Future<SheetStatus> ping(String scriptUrl, String token) async {
    final Object? data;
    try {
      data = await _withRetry((_) => _get(scriptUrl, token, 'ping'));
    } on SheetException catch (e) {
      if (e.message.startsWith('Unknown action: ping')) {
        throw const SheetException(
            'The deployment is running old code. Paste the latest Code.gs, then '
            '$_redeployHint');
      }
      rethrow;
    }
    if (data is! Map) throw const SheetException('Unexpected response from sheet.');
    return SheetStatus(
      version: (data['version'] as num?)?.toInt() ?? 0,
      count: (data['count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Podcast> add(String scriptUrl, String token, Podcast podcast) {
    return _withRetry((isRetry) async {
      try {
        final data = await _post(scriptUrl, {
          'token': token,
          'action': 'add',
          'podcast': podcast.toJson(),
        });
        return Podcast.fromJson(data as Map<String, dynamic>);
      } on DuplicatePodcastException catch (e) {
        // The first attempt reached the sheet; only its answer got lost.
        if (isRetry && e.existingId == podcast.id) return podcast;
        rethrow;
      }
    });
  }

  Future<Podcast> update(String scriptUrl, String token, Podcast podcast) async {
    final data = await _withRetry((_) => _post(scriptUrl, {
          'token': token,
          'action': 'update',
          'podcast': podcast.toJson(),
        }));
    return Podcast.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String scriptUrl, String token, String id) {
    return _withRetry((isRetry) async {
      try {
        await _post(scriptUrl, {'token': token, 'action': 'delete', 'id': id});
      } on SheetException catch (e) {
        // The first attempt already deleted the row.
        if (isRetry && e.message.startsWith('Podcast not found')) return;
        rethrow;
      }
    });
  }

  /// Validates the Script URL and turns common wrong variants into the
  /// public /exec URL.
  static Uri parseUrl(String scriptUrl) {
    final uri = Uri.tryParse(scriptUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SheetException('Invalid Script URL. Set it in Settings.');
    }
    if (uri.host != 'script.google.com') return uri;

    final segments = [...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    // With several Google accounts signed in, the URL gets "/u/1/", which
    // needs a login. The plain form works for everyone.
    if (segments.length >= 3 && segments[0] == 'macros' && segments[1] == 'u') {
      segments.removeRange(1, 3);
    }
    final last = segments.isEmpty ? '' : segments.last;
    if (last == 'dev') {
      throw const SheetException(
          'This is the test URL (ends with /dev), which only works while signed '
          'in. Use the Web app URL ending with /exec.');
    }
    if (last != 'exec') {
      throw const SheetException(
          'This is not the Web app URL. Copy the URL ending with /exec from '
          'Deploy → Manage deployments.');
    }
    return uri.replace(pathSegments: segments);
  }

  // -------------------------------------------------------------------------

  /// Runs [fn], and once more after [retryDelay] if it failed transiently.
  Future<T> _withRetry<T>(Future<T> Function(bool isRetry) fn) async {
    try {
      return await fn(false);
    } on SheetException catch (e) {
      if (!e.transient) rethrow;
      await Future<void>.delayed(retryDelay);
      return fn(true);
    }
  }

  Future<Object?> _get(String scriptUrl, String token, String action) async {
    final base = parseUrl(scriptUrl);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      'action': action,
      'token': token,
    });
    final res = await _send(() => _client.get(uri));
    return _unwrap(res);
  }

  Future<Object?> _post(String scriptUrl, Map<String, dynamic> body) async {
    final uri = parseUrl(scriptUrl);
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
      return await fn().timeout(timeout);
    } on SheetException {
      rethrow;
    } on TimeoutException {
      throw const SheetException(
          'The sheet took too long to answer. Check your connection and try again.',
          transient: true);
    } catch (e) {
      throw SheetException(
          'Could not reach the sheet. Check your internet connection. ($e)',
          transient: true);
    }
  }

  Object? _unwrap(http.Response res) {
    if (res.statusCode != 200) throw _httpError(res.statusCode);

    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final Object? json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      throw _pageError(body);
    }
    if (json is! Map<String, dynamic>) throw _pageError(body);
    if (json['ok'] == true) return json['data'];

    final error = json['error']?.toString() ?? 'Unknown error';
    if (error.startsWith('DUPLICATE:')) {
      throw DuplicatePodcastException(error.substring('DUPLICATE:'.length));
    }
    if (error.startsWith('Unauthorized')) {
      throw SheetException(
          '$error. Check that the token in Settings matches TOKEN in Code.gs. '
          'If you changed TOKEN in the code, $_redeployHint '
          'Or set TOKEN in Project Settings → Script properties.');
    }
    if (error.startsWith('Sheet is busy')) {
      throw SheetException(error, transient: true);
    }
    throw SheetException(error);
  }

  static SheetException _httpError(int status) {
    if (status == 401 || status == 403) {
      return SheetException(
          'Access denied (HTTP $status). In Apps Script, set the deployment\'s '
          '"Who has access" to Anyone.');
    }
    if (status == 404) {
      return const SheetException(
          'Script URL not found (HTTP 404). The deployment may be deleted or '
          'archived, or the URL is wrong. Copy the /exec URL from Deploy → '
          'Manage deployments.');
    }
    if (status == 429) {
      return const SheetException('Google quota reached (HTTP 429). Try again later.',
          transient: true);
    }
    if (status >= 500) {
      return SheetException('Google Apps Script error (HTTP $status). Try again.',
          transient: true);
    }
    return SheetException('Sheet request failed (HTTP $status).');
  }

  /// Explains an HTML page returned instead of JSON.
  static SheetException _pageError(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('authorization is required')) {
      return const SheetException(
          'The script needs permission. In Apps Script, run setup and grant '
          'access, then $_redeployHint');
    }
    if (lower.contains('script function not found')) {
      return const SheetException(
          'The deployment has no doGet/doPost. Paste Code.gs, then $_redeployHint');
    }
    if (lower.contains('accounts.google.com') || lower.contains('sign in')) {
      return const SheetException(
          'Google asked for a sign-in instead of returning data. In Apps Script, '
          'set the deployment\'s "Who has access" to Anyone.');
    }
    final title = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true)
        .firstMatch(body)
        ?.group(1)
        ?.trim();
    return SheetException(
        'Sheet returned an unexpected page${title == null || title.isEmpty ? '' : ' ("$title")'}. '
        'Check the Script URL and that the web app is deployed with access "Anyone".');
  }
}
