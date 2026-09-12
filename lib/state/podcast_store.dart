import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/podcast.dart';
import '../services/settings_service.dart';
import '../services/sheet_service.dart';

enum SortMode { rank, dateAdded }

class PodcastStore extends ChangeNotifier {
  PodcastStore({SheetService? sheet, SettingsService? settings})
      : _sheet = sheet ?? SheetService(),
        _settings = settings ?? SettingsService();

  final SheetService _sheet;
  final SettingsService _settings;

  List<Podcast> _all = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  SortMode _sortMode = SortMode.rank;
  String _scriptUrl = '';
  String _token = '';
  bool _initialized = false;

  bool get loading => _loading;
  String? get error => _error;
  String get query => _query;
  SortMode get sortMode => _sortMode;
  String get scriptUrl => _scriptUrl;
  String get token => _token;
  bool get initialized => _initialized;
  bool get isConfigured => _scriptUrl.isNotEmpty && _token.isNotEmpty;
  int get totalCount => _all.length;

  /// Filtered by search query and sorted by the selected mode.
  List<Podcast> get podcasts {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<Podcast>.of(_all)
        : _all
            .where((p) =>
                p.title.toLowerCase().contains(q) ||
                p.channel.toLowerCase().contains(q) ||
                p.points.any((point) => point.toLowerCase().contains(q)))
            .toList();
    list.sort(_compare);
    return list;
  }

  int _compare(Podcast a, Podcast b) {
    final byDate = (b.dateAdded ?? DateTime(0)).compareTo(a.dateAdded ?? DateTime(0));
    if (_sortMode == SortMode.rank) {
      final byRank = b.rank.compareTo(a.rank);
      return byRank != 0 ? byRank : byDate;
    }
    return byDate;
  }

  Podcast? byId(String id) {
    for (final p in _all) {
      if (p.id == id) return p;
    }
    return null;
  }

  Podcast? byVideoId(String videoId) {
    for (final p in _all) {
      if (p.videoId == videoId) return p;
    }
    return null;
  }

  Future<void> init() async {
    _scriptUrl = await _settings.getScriptUrl();
    _token = await _settings.getToken();
    _all = await _settings.loadCache();
    _initialized = true;
    notifyListeners();
    // Load fresh data in the background; the cached list shows meanwhile.
    if (isConfigured) unawaited(refresh());
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  void setSortMode(SortMode mode) {
    _sortMode = mode;
    notifyListeners();
  }

  Future<void> saveSettings(String scriptUrl, String token) async {
    await _settings.save(scriptUrl: scriptUrl, token: token);
    _scriptUrl = scriptUrl.trim();
    _token = token.trim();
    notifyListeners();
    // Load in the background so Settings can close right away; the home
    // screen shows progress and any error.
    unawaited(refresh());
  }

  /// Checks that the given URL/token work, without saving them.
  Future<int> testConnection(String scriptUrl, String token) async {
    final list = await _sheet.list(scriptUrl.trim(), token.trim());
    return list.length;
  }

  Future<void> refresh() async {
    if (!isConfigured) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _sheet.list(_scriptUrl, _token);
      await _settings.saveCache(_all);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Shows [podcast] in the list right away, then saves it to the sheet.
  /// If saving fails, it is removed again and the error is rethrown.
  Future<Podcast> add(Podcast podcast) async {
    _all = [..._all.where((p) => p.id != podcast.id), podcast];
    notifyListeners();
    try {
      final saved = await _sheet.add(_scriptUrl, _token, podcast);
      _all = [..._all.where((p) => p.id != saved.id), saved];
      await _persist();
      return saved;
    } catch (_) {
      _all = _all.where((p) => p.id != podcast.id).toList();
      notifyListeners();
      rethrow;
    }
  }

  /// Shows the change right away, then saves it to the sheet.
  /// If saving fails, the previous version is restored and the error is rethrown.
  Future<Podcast> update(Podcast podcast) async {
    final previous = byId(podcast.id);
    _all = [for (final p in _all) p.id == podcast.id ? podcast : p];
    notifyListeners();
    try {
      final saved = await _sheet.update(_scriptUrl, _token, podcast);
      _all = [for (final p in _all) p.id == saved.id ? saved : p];
      await _persist();
      return saved;
    } catch (_) {
      if (previous != null) {
        _all = [for (final p in _all) p.id == podcast.id ? previous : p];
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _sheet.delete(_scriptUrl, _token, id);
    _all = _all.where((p) => p.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    _error = null;
    notifyListeners();
    await _settings.saveCache(_all);
  }
}
