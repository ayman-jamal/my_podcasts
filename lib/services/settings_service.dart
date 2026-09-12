import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/podcast.dart';

class SettingsService {
  static const _scriptUrlKey = 'script_url';
  static const _tokenKey = 'token';
  static const _cacheKey = 'podcasts_cache';

  /// Removes invisible characters (zero-width, BOM) and surrounding
  /// whitespace (including non-breaking spaces) that sneak in when a token
  /// is pasted on a phone.
  static String cleanToken(String token) =>
      token.replaceAll(RegExp('[\u200B-\u200D\u2060\uFEFF]'), '').trim();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String> getScriptUrl() async => (await _prefs).getString(_scriptUrlKey) ?? '';

  Future<String> getToken() async => cleanToken((await _prefs).getString(_tokenKey) ?? '');

  Future<void> save({required String scriptUrl, required String token}) async {
    final prefs = await _prefs;
    await prefs.setString(_scriptUrlKey, scriptUrl.trim());
    await prefs.setString(_tokenKey, cleanToken(token));
  }

  Future<List<Podcast>> loadCache() async {
    final raw = (await _prefs).getString(_cacheKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(Podcast.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCache(List<Podcast> podcasts) async {
    await (await _prefs)
        .setString(_cacheKey, jsonEncode(podcasts.map((p) => p.toJson()).toList()));
  }
}
