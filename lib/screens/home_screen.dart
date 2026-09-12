import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/podcast.dart';
import '../services/youtube_service.dart';
import '../state/podcast_store.dart';
import '../widgets/podcast_tile.dart';
import 'add_edit_screen.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addFromClipboard() async {
    final navigator = Navigator.of(context);
    String? text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      text = null;
    }
    // Only prefill when the clipboard really holds a YouTube link.
    final prefill = YoutubeService.extractVideoId(text) != null ? text : null;
    await openAddFlow(navigator, prefill);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PodcastStore>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('My Podcasts'),
            if (store.isConfigured && store.totalCount > 0) ...[
              const SizedBox(width: 8),
              // Total podcasts; while searching, "matches of total".
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  store.query.trim().isEmpty
                      ? '${store.totalCount}'
                      : '${store.podcasts.length} of ${store.totalCount}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          PopupMenuButton<SortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: store.setSortMode,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: SortMode.rank,
                checked: store.sortMode == SortMode.rank,
                child: const Text('Sort by rank'),
              ),
              CheckedPopupMenuItem(
                value: SortMode.dateAdded,
                checked: store.sortMode == SortMode.dateAdded,
                child: const Text('Sort by date added'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
        bottom: store.isConfigured
            ? PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SearchBar(
                    controller: _search,
                    hintText: 'Search podcasts or points',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll(0.0),
                    onChanged: store.setQuery,
                    trailing: [
                      if (_search.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            store.setQuery('');
                          },
                        ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: _buildBody(store),
      floatingActionButton: store.isConfigured
          ? FloatingActionButton.extended(
              onPressed: _addFromClipboard,
              icon: const Icon(Icons.add_link),
              label: const Text('Add podcast'),
            )
          : null,
    );
  }

  Widget _buildBody(PodcastStore store) {
    if (!store.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!store.isConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.table_chart_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Connect your Google Sheet to start saving podcasts.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.link),
                label: const Text('Connect sheet'),
              ),
            ],
          ),
        ),
      );
    }

    final items = store.podcasts;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        children: [
          if (store.loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (store.error != null) _ErrorCard(message: store.error!, onRetry: store.refresh),
          if (items.isEmpty && !store.loading)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                store.query.isNotEmpty
                    ? 'No podcasts match "${store.query}".'
                    : 'No podcasts yet.\nShare an episode from YouTube, or copy its '
                        'link and tap "Add podcast".',
                textAlign: TextAlign.center,
              ),
            ),
          for (final Podcast p in items)
            PodcastTile(
              key: ValueKey(p.id),
              podcast: p,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetailScreen(podcastId: p.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: ListTile(
        leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
        title: Text(
          'Could not load from the sheet',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        subtitle: Text(
          '$message\nShowing the last saved copy.',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        trailing: IconButton(
          icon: Icon(Icons.refresh, color: scheme.onErrorContainer),
          onPressed: onRetry,
        ),
      ),
    );
  }
}
