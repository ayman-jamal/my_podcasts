import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/podcast.dart';

class PodcastTile extends StatelessWidget {
  const PodcastTile({super.key, required this.podcast, required this.onTap});

  final Podcast podcast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Thumbnail(url: podcast.thumbnailUrl),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: RankBadge(rank: podcast.rank),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      podcast.title.isEmpty ? 'Untitled episode' : podcast.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      podcast.channel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${podcast.points.length} '
                      '${podcast.points.length == 1 ? 'point' : 'points'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Thumbnail extends StatelessWidget {
  const Thumbnail({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => ColoredBox(color: color),
      errorWidget: (_, _, _) => ColoredBox(
        color: color,
        child: const Icon(Icons.podcasts),
      ),
    );
  }
}

class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank, this.large = false});

  final int rank;
  final bool large;

  static Color colorFor(int rank) {
    if (rank >= 8) return Colors.green.shade700;
    if (rank >= 5) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 7,
        vertical: large ? 6 : 3,
      ),
      decoration: BoxDecoration(
        color: colorFor(rank),
        borderRadius: BorderRadius.circular(large ? 16 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: large ? 18 : 12, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            large ? '$rank / 10' : '$rank',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: large ? 16 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
