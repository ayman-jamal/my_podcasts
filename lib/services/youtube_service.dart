import 'dart:convert';

import 'package:http/http.dart' as http;

class VideoInfo {
  final String videoId;
  final String title;
  final String channel;

  const VideoInfo({
    required this.videoId,
    required this.title,
    required this.channel,
  });

  String get url => YoutubeService.watchUrl(videoId);
  String get thumbnailUrl => YoutubeService.thumbnailUrl(videoId);
}

class YoutubeService {
  YoutubeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _urlPattern = RegExp(r'''(https?://)?[^\s<>"']*youtu[^\s<>"']*''',
      caseSensitive: false);

  static String watchUrl(String videoId) =>
      'https://www.youtube.com/watch?v=$videoId';

  static String thumbnailUrl(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  /// Finds a YouTube video id inside any text: a bare link, or the text the
  /// YouTube app shares (which may include a title before the link).
  static String? extractVideoId(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (_idPattern.hasMatch(trimmed)) return trimmed;

    for (final match in _urlPattern.allMatches(trimmed)) {
      final id = _idFromUrl(match.group(0)!);
      if (id != null) return id;
    }
    return null;
  }

  static String? _idFromUrl(String raw) {
    var candidate = raw;
    if (!candidate.toLowerCase().startsWith('http')) {
      candidate = 'https://$candidate';
    }
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? id;

    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      if (segments.isNotEmpty) id = segments.first;
    } else if (host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com')) {
      if (uri.queryParameters['v'] != null) {
        id = uri.queryParameters['v'];
      } else if (segments.length >= 2 &&
          const ['shorts', 'live', 'embed', 'v', 'e'].contains(segments[0])) {
        id = segments[1];
      }
    }

    if (id != null && _idPattern.hasMatch(id)) return id;
    return null;
  }

  /// Fetches title and channel name via YouTube's public oEmbed endpoint.
  /// Falls back to empty strings when the lookup fails, so saving still works.
  Future<VideoInfo> fetchInfo(String videoId) async {
    try {
      final uri = Uri.https('www.youtube.com', '/oembed', {
        'url': watchUrl(videoId),
        'format': 'json',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return VideoInfo(
          videoId: videoId,
          title: json['title']?.toString() ?? '',
          channel: json['author_name']?.toString() ?? '',
        );
      }
    } catch (_) {
      // ignore: fall through to an empty result
    }
    return VideoInfo(videoId: videoId, title: '', channel: '');
  }
}
