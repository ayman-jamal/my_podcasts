class Podcast {
  final String id;
  final String videoId;
  final String title;
  final String channel;
  final String url;
  final String thumbnailUrl;
  final int rank;
  final List<String> points;
  final DateTime? dateAdded;
  final DateTime? lastUpdated;

  const Podcast({
    required this.id,
    required this.videoId,
    required this.title,
    required this.channel,
    required this.url,
    required this.thumbnailUrl,
    required this.rank,
    required this.points,
    this.dateAdded,
    this.lastUpdated,
  });

  Podcast copyWith({
    String? title,
    String? channel,
    int? rank,
    List<String>? points,
    DateTime? dateAdded,
    DateTime? lastUpdated,
  }) {
    return Podcast(
      id: id,
      videoId: videoId,
      title: title ?? this.title,
      channel: channel ?? this.channel,
      url: url,
      thumbnailUrl: thumbnailUrl,
      rank: rank ?? this.rank,
      points: points ?? this.points,
      dateAdded: dateAdded ?? this.dateAdded,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  factory Podcast.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final List<String> points;
    if (rawPoints is List) {
      points = rawPoints
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      points = splitPoints(rawPoints?.toString() ?? '');
    }
    final videoId = json['videoId']?.toString() ?? '';
    return Podcast(
      id: json['id']?.toString() ?? '',
      videoId: videoId,
      title: json['title']?.toString() ?? '',
      channel: json['channel']?.toString() ?? '',
      url: _nonEmpty(json['url']) ?? 'https://www.youtube.com/watch?v=$videoId',
      thumbnailUrl: _nonEmpty(json['thumbnailUrl']) ??
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      rank: int.tryParse(json['rank']?.toString() ?? '') ??
          (num.tryParse(json['rank']?.toString() ?? '')?.round() ?? 0),
      points: points,
      dateAdded: DateTime.tryParse(json['dateAdded']?.toString() ?? ''),
      lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'channel': channel,
        'url': url,
        'thumbnailUrl': thumbnailUrl,
        'rank': rank,
        'points': points,
        'dateAdded': dateAdded?.toIso8601String(),
        'lastUpdated': lastUpdated?.toIso8601String(),
      };

  /// ["foo", "bar"] -> "1. foo\n2. bar"
  static String joinPoints(List<String> points) {
    final cleaned = points
        .map((p) => p.replaceAll(RegExp(r'\r?\n'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return [for (var i = 0; i < cleaned.length; i++) '${i + 1}. ${cleaned[i]}']
        .join('\n');
  }

  /// "1. foo\n2. bar" -> ["foo", "bar"]
  static List<String> splitPoints(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.replaceFirst(RegExp(r'^\s*\d+[.)]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static String? _nonEmpty(Object? value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
}
