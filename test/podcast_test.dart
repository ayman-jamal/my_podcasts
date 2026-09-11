import 'package:flutter_test/flutter_test.dart';
import 'package:my_podcasts/models/podcast.dart';

void main() {
  group('points text', () {
    test('joinPoints numbers lines and drops blanks', () {
      expect(
        Podcast.joinPoints(['first', '  second ', '', 'multi\nline']),
        '1. first\n2. second\n3. multi line',
      );
    });

    test('splitPoints strips numbering and blanks', () {
      expect(
        Podcast.splitPoints('1. first\n2) second\n\n  3.  third  \r\nno number'),
        ['first', 'second', 'third', 'no number'],
      );
    });

    test('round trip', () {
      const points = ['Sleep matters', 'Walk daily', 'Read 10 pages'];
      expect(Podcast.splitPoints(Podcast.joinPoints(points)), points);
    });
  });

  group('json', () {
    test('fromJson accepts sheet values', () {
      final p = Podcast.fromJson({
        'id': 'abc',
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Episode',
        'channel': 'Show',
        'url': '',
        'thumbnailUrl': null,
        'rank': 8.0,
        'points': '1. one\n2. two',
        'dateAdded': '2026-09-12T10:00:00.000Z',
      });
      expect(p.rank, 8);
      expect(p.points, ['one', 'two']);
      expect(p.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(p.thumbnailUrl, 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
      expect(p.dateAdded, DateTime.utc(2026, 9, 12, 10));
    });

    test('toJson / fromJson round trip', () {
      final p = Podcast(
        id: 'id-1',
        videoId: 'dQw4w9WgXcQ',
        title: 'T',
        channel: 'C',
        url: 'https://youtu.be/dQw4w9WgXcQ',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        rank: 10,
        points: const ['a', 'b'],
        dateAdded: DateTime.utc(2026, 1, 2),
      );
      final back = Podcast.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
    });
  });
}
