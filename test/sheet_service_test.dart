import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_podcasts/models/podcast.dart';
import 'package:my_podcasts/services/settings_service.dart';
import 'package:my_podcasts/services/sheet_service.dart';

void main() {
  const url = 'https://script.google.com/macros/s/ABC/exec';
  const token = 'secret';
  const podcast = Podcast(
    id: 'id-1',
    videoId: 'dQw4w9WgXcQ',
    title: 'T',
    channel: 'C',
    url: 'https://youtu.be/dQw4w9WgXcQ',
    thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    rank: 8,
    points: ['a'],
  );

  http.Response ok(Object? data) =>
      http.Response(jsonEncode({'ok': true, 'data': data}), 200);
  http.Response fail(String error) =>
      http.Response(jsonEncode({'ok': false, 'error': error}), 200);

  // Number of requests the mock client has answered.
  var calls = 0;
  SheetService service(
    FutureOr<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    calls = 0;
    return SheetService(
      client: MockClient((request) async {
        calls++;
        return handler(request);
      }),
      timeout: timeout,
      retryDelay: Duration.zero,
    );
  }

  Matcher throwsSheet(String text) => throwsA(
      isA<SheetException>().having((e) => e.message, 'message', contains(text)));

  group('parseUrl', () {
    test('removes the /u/<n>/ account segment', () {
      expect(
        SheetService.parseUrl('https://script.google.com/macros/u/1/s/ABC/exec').toString(),
        url,
      );
    });

    test('accepts a trailing slash', () {
      expect(SheetService.parseUrl('$url/').toString(), url);
    });

    test('rejects the /dev test URL', () {
      expect(() => SheetService.parseUrl('https://script.google.com/macros/s/ABC/dev'),
          throwsSheet('/exec'));
    });

    test('rejects the editor URL', () {
      expect(() => SheetService.parseUrl('https://script.google.com/home/projects/ABC/edit'),
          throwsSheet('/exec'));
    });

    test('rejects text that is not a URL', () {
      expect(() => SheetService.parseUrl('not a url'), throwsSheet('Invalid Script URL'));
    });
  });

  group('responses', () {
    test('list sends action and token', () async {
      final svc = service((r) {
        expect(r.method, 'GET');
        expect(r.url.queryParameters, {'action': 'list', 'token': token});
        return ok([podcast.toJson()]);
      });
      expect((await svc.list(url, token)).single.id, 'id-1');
    });

    test('follows the POST redirect with a GET', () async {
      final svc = service((r) {
        if (r.method == 'POST') {
          expect(jsonDecode(r.body)['action'], 'update');
          return http.Response('', 302, headers: {
            'location': 'https://script.googleusercontent.com/macros/echo?k=1',
          });
        }
        expect(r.url.host, 'script.googleusercontent.com');
        return ok(podcast.toJson());
      });
      expect((await svc.update(url, token, podcast)).id, 'id-1');
      expect(calls, 2);
    });

    test('403 explains the access setting and is not retried', () async {
      final svc = service((_) => http.Response('', 403));
      await expectLater(svc.list(url, token), throwsSheet('Who has access'));
      expect(calls, 1);
    });

    test('404 explains the URL is not found', () async {
      final svc = service((_) => http.Response('', 404));
      await expectLater(svc.list(url, token), throwsSheet('HTTP 404'));
    });

    test('500 is retried once and can then succeed', () async {
      final svc = service((_) => calls == 1 ? http.Response('', 500) : ok([]));
      expect(await svc.list(url, token), isEmpty);
      expect(calls, 2);
    });

    test('500 twice fails after one retry', () async {
      final svc = service((_) => http.Response('', 500));
      await expectLater(svc.list(url, token), throwsSheet('HTTP 500'));
      expect(calls, 2);
    });

    test('timeout is retried and then explained', () async {
      final svc = service(
        (_) => Future.delayed(const Duration(milliseconds: 200), () => ok([])),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(svc.list(url, token), throwsSheet('too long'));
      expect(calls, 2);
    });

    test('Google sign-in page explains the access setting', () async {
      final svc = service((_) => http.Response(
          '<html><head><title>Sign in - Google Accounts</title></head>'
          '<body><a href="https://accounts.google.com/">x</a></body></html>',
          200));
      await expectLater(svc.list(url, token), throwsSheet('Who has access'));
    });

    test('authorization page says to run setup', () async {
      final svc = service(
          (_) => http.Response('<html>Authorization is required to perform that action.</html>', 200));
      await expectLater(svc.list(url, token), throwsSheet('run setup'));
    });

    test('other pages show their title', () async {
      final svc = service((_) => http.Response('<html><title>Error</title></html>', 200));
      await expectLater(svc.list(url, token), throwsSheet('("Error")'));
    });

    test('unauthorized explains how to fix the token', () async {
      final svc = service((_) => fail('Unauthorized: invalid token'));
      await expectLater(svc.list(url, token), throwsSheet('New version'));
      expect(calls, 1);
    });
  });

  group('retries of writes', () {
    test('add succeeds when the retry finds its own row', () async {
      final svc = service((_) =>
          calls == 1 ? throw http.ClientException('Connection closed') : fail('DUPLICATE:id-1'));
      expect((await svc.add(url, token, podcast)).id, 'id-1');
      expect(calls, 2);
    });

    test('add of an existing video still reports the duplicate', () async {
      final svc = service((_) => fail('DUPLICATE:other-id'));
      await expectLater(
          svc.add(url, token, podcast), throwsA(isA<DuplicatePodcastException>()));
      expect(calls, 1);
    });

    test('delete succeeds when the retry finds the row already gone', () async {
      final svc = service((_) => calls == 1
          ? throw http.ClientException('Connection closed')
          : fail('Podcast not found: id-1'));
      await svc.delete(url, token, 'id-1');
      expect(calls, 2);
    });
  });

  group('ping', () {
    test('returns version and count', () async {
      final svc = service((r) {
        expect(r.url.queryParameters['action'], 'ping');
        return ok({'version': 2, 'sheet': 'Podcasts', 'count': 3});
      });
      final status = await svc.ping(url, token);
      expect(status.version, 2);
      expect(status.count, 3);
    });

    test('detects a deployment running old code', () async {
      final svc = service((_) => fail('Unknown action: ping'));
      await expectLater(svc.ping(url, token), throwsSheet('old code'));
    });
  });

  test('cleanToken strips invisible characters and spaces', () {
    expect(SettingsService.cleanToken('\u200B my-token\u00A0\uFEFF\n'), 'my-token');
  });
}
