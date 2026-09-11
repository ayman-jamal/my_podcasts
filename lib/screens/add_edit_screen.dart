import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/podcast.dart';
import '../services/sheet_service.dart';
import '../services/youtube_service.dart';
import '../state/podcast_store.dart';
import '../widgets/podcast_tile.dart';
import 'settings_screen.dart';

/// Single entry point for adding a podcast. Used by both the YouTube share
/// sheet and the in-app "Add podcast" button (paste), so both end up in the
/// exact same flow.
Future<void> openAddFlow(NavigatorState navigator, String? rawText) async {
  final context = navigator.context;
  final store = context.read<PodcastStore>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (!store.isConfigured) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Connect your Google Sheet first.')),
    );
    await navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (!store.isConfigured) return;
  }

  final videoId = YoutubeService.extractVideoId(rawText);
  if (videoId != null) {
    final existing = store.byVideoId(videoId);
    if (existing != null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Already in your list. Opening it for editing.')),
      );
      await navigator.push(
        MaterialPageRoute(builder: (_) => AddEditScreen(existing: existing)),
      );
      return;
    }
  }

  await navigator.push(
    MaterialPageRoute(builder: (_) => AddEditScreen(initialText: rawText)),
  );
}

class AddEditScreen extends StatefulWidget {
  const AddEditScreen({super.key, this.existing, this.initialText});

  /// When set, the screen edits this podcast (link is locked).
  final Podcast? existing;

  /// Shared or pasted text containing a YouTube link.
  final String? initialText;

  @override
  State<AddEditScreen> createState() => _AddEditScreenState();
}

class _AddEditScreenState extends State<AddEditScreen> {
  final _youtube = YoutubeService();
  final _link = TextEditingController();
  final _pointCtrl = TextEditingController();
  final _pointFocus = FocusNode();

  VideoInfo? _info;
  bool _loadingInfo = false;
  String? _linkError;
  int? _rank;
  final List<String> _points = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _link.text = existing.url;
      _info = VideoInfo(
        videoId: existing.videoId,
        title: existing.title,
        channel: existing.channel,
      );
      _rank = existing.rank;
      _points.addAll(existing.points);
    } else if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _link.text = widget.initialText!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveLink());
    }
    _pointCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _link.dispose();
    _pointCtrl.dispose();
    _pointFocus.dispose();
    super.dispose();
  }

  // --- Link -----------------------------------------------------------------

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    _link.text = text;
    await _resolveLink();
  }

  void _onLinkChanged(String text) {
    final id = YoutubeService.extractVideoId(text);
    if (id != null && id != _info?.videoId) {
      _resolveLink();
    } else if (id == null && (_info != null || _linkError != null)) {
      setState(() {
        _info = null;
        _linkError = null;
      });
    }
  }

  Future<void> _resolveLink() async {
    final id = YoutubeService.extractVideoId(_link.text);
    if (id == null) {
      setState(() {
        _info = null;
        _linkError = 'This is not a valid YouTube link';
      });
      return;
    }

    final existing = context.read<PodcastStore>().byVideoId(id);
    if (existing != null) {
      await _offerEditExisting(existing);
      return;
    }

    setState(() {
      _loadingInfo = true;
      _linkError = null;
    });
    final info = await _youtube.fetchInfo(id);
    if (!mounted) return;
    // Ignore a stale result if the link changed while loading.
    if (YoutubeService.extractVideoId(_link.text) != id) {
      setState(() => _loadingInfo = false);
      return;
    }
    setState(() {
      _info = info;
      _loadingInfo = false;
    });
  }

  Future<void> _offerEditExisting(Podcast existing) async {
    final edit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Already in your list'),
        content: Text(
          'You already saved "${existing.title.isEmpty ? 'this episode' : existing.title}". '
          'Do you want to edit it instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Edit it'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (edit == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AddEditScreen(existing: existing)),
      );
    } else {
      setState(() {
        _info = null;
        _link.clear();
      });
    }
  }

  // --- Points ---------------------------------------------------------------

  void _addNextPoint() {
    final text = _pointCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _points.add(text));
    _pointCtrl.clear();
    _pointFocus.requestFocus();
  }

  Future<void> _editPoint(int index) async {
    final controller = TextEditingController(text: _points[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit point ${index + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _points[index] = result);
    }
  }

  void _removePoint(int index) => setState(() => _points.removeAt(index));

  /// Locked points plus the one currently being typed (if any).
  List<String> get _allPoints => [
        ..._points,
        if (_pointCtrl.text.trim().isNotEmpty) _pointCtrl.text.trim(),
      ];

  // --- Submit ---------------------------------------------------------------

  String? get _missing {
    if (_info == null) return 'Add a YouTube link';
    if (_rank == null) return 'Pick a rank';
    if (_allPoints.isEmpty) return 'Write at least one point';
    return null;
  }

  bool get _canSubmit => _missing == null && !_saving && !_loadingInfo;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final store = context.read<PodcastStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final info = _info!;

    try {
      final existing = widget.existing;
      if (existing != null) {
        await store.update(existing.copyWith(rank: _rank, points: _allPoints));
        messenger.showSnackBar(const SnackBar(content: Text('Podcast updated')));
      } else {
        await store.add(Podcast(
          id: const Uuid().v4(),
          videoId: info.videoId,
          title: info.title,
          channel: info.channel,
          url: info.url,
          thumbnailUrl: info.thumbnailUrl,
          rank: _rank!,
          points: _allPoints,
        ));
        messenger.showSnackBar(
          const SnackBar(content: Text('Podcast saved to your sheet')),
        );
      }
      navigator.pop(true);
    } on DuplicatePodcastException catch (e) {
      await store.refresh();
      if (!mounted) return;
      setState(() => _saving = false);
      final existing = store.byId(e.existingId);
      if (existing != null) {
        await _offerEditExisting(existing);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit podcast' : 'Add podcast')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionTitle('1. Episode'),
                if (!_isEdit)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _link,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: 'YouTube link',
                            hintText: 'https://youtu.be/...',
                            border: const OutlineInputBorder(),
                            errorText: _linkError,
                          ),
                          onChanged: _onLinkChanged,
                          onSubmitted: (_) => _resolveLink(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton.filledTonal(
                          tooltip: 'Paste',
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste),
                        ),
                      ),
                    ],
                  ),
                if (_loadingInfo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_info != null) ...[
                  const SizedBox(height: 12),
                  _EpisodePreview(info: _info!),
                ],
                const SizedBox(height: 24),
                _SectionTitle('2. Rank (1–10)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var r = 1; r <= 10; r++)
                      ChoiceChip(
                        label: SizedBox(
                          width: 22,
                          child: Text('$r', textAlign: TextAlign.center),
                        ),
                        selected: _rank == r,
                        selectedColor: RankBadge.colorFor(r).withValues(alpha: 0.35),
                        onSelected: (_) => setState(() => _rank = r),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionTitle('3. What did you learn?'),
                for (var i = 0; i < _points.length; i++)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                      title: Text(_points[i]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editPoint(i),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () => _removePoint(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextField(
                  controller: _pointCtrl,
                  focusNode: _pointFocus,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _addNextPoint(),
                  decoration: InputDecoration(
                    labelText: 'Point ${_points.length + 1}',
                    hintText: 'Something you learned…',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed:
                        _pointCtrl.text.trim().isNotEmpty ? _addNextPoint : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Add next point'),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_missing != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_missing!, style: theme.textTheme.bodySmall),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _canSubmit ? _submit : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isEdit ? 'Save changes' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _EpisodePreview extends StatelessWidget {
  const _EpisodePreview({required this.info});

  final VideoInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Thumbnail(url: info.thumbnailUrl),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title.isEmpty ? 'Title unavailable' : info.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (info.channel.isNotEmpty)
                    Text(info.channel, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
