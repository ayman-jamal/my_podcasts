import 'package:flutter_test/flutter_test.dart';
import 'package:my_podcasts/services/youtube_service.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('extractVideoId finds the id in', () {
    final cases = <String, String>{
      'https://www.youtube.com/watch?v=$id': id,
      'https://youtube.com/watch?v=$id&t=42s': id,
      'https://m.youtube.com/watch?v=$id': id,
      'https://music.youtube.com/watch?v=$id&list=RDAMVM': id,
      'https://youtu.be/$id': id,
      'https://youtu.be/$id?si=AbCdEf123_xyz': id,
      'https://www.youtube.com/shorts/$id': id,
      'https://www.youtube.com/live/$id?feature=share': id,
      'https://www.youtube.com/embed/$id': id,
      'youtube.com/watch?v=$id': id,
      'Great episode about habits\nhttps://youtu.be/$id?si=xyz': id,
      'Check this out: https://www.youtube.com/watch?v=$id !': id,
      'youtube: https://youtu.be/$id': id,
      '  https://youtu.be/$id  ': id,
      id: id,
    };
    cases.forEach((input, expected) {
      test(input, () => expect(YoutubeService.extractVideoId(input), expected));
    });
  });

  group('extractVideoId returns null for', () {
    final invalid = <String?>[
      null,
      '',
      'hello world',
      'https://vimeo.com/123456',
      'https://www.youtube.com/',
      'https://www.youtube.com/watch?v=short',
      'https://example.com/watch?v=$id',
    ];
    for (final input in invalid) {
      test('$input', () => expect(YoutubeService.extractVideoId(input), isNull));
    }
  });

  test('builds thumbnail and watch urls', () {
    expect(YoutubeService.thumbnailUrl(id), 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
    expect(YoutubeService.watchUrl(id), 'https://www.youtube.com/watch?v=$id');
  });
}
