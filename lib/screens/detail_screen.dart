import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/podcast_store.dart';
import '../widgets/podcast_tile.dart';
import 'add_edit_screen.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.podcastId});

  final String podcastId;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete podcast?'),
        content: const Text('This also removes its row from the Google Sheet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final store = context.read<PodcastStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.delete(podcastId);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Podcast deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final podcast = context.watch<PodcastStore>().byId(podcastId);
    if (podcast == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Podcast not found')),
      );
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Podcast'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddEditScreen(existing: podcast)),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Thumbnail(url: podcast.thumbnailUrl),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  podcast.title.isEmpty ? 'Untitled episode' : podcast.title,
                  style: theme.textTheme.titleLarge,
                ),
                if (podcast.channel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(podcast.channel, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    RankBadge(rank: podcast.rank, large: true),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(podcast.url),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Open in YouTube'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text('What I learned', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < podcast.points.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              podcast.points[i],
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
