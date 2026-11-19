import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  Future<String> getServer() async => await _prefs.getString('server') ?? 'http://192.168.1.107:9999/';
  Future<void> setServer(String url) => _prefs.setString('server', url);

  Future<Map<String, dynamic>> _getHistory() async {
    try {
      final raw = await _prefs.getString('history');
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }
  Future<Duration?> position(Uri uri) async {
    final h = await _getHistory();
    final record = h[uri.toString()];
    if (record is! Map) return null;
    final value = record['positionMs'];
    return value is num ? Duration(milliseconds: value.toInt()) : null;
  }
  Future<void> record(Uri uri, String title, Duration position, Duration duration) async {
    final h = await _getHistory();
    final complete = duration.inSeconds > 0 && (duration - position).inSeconds <= 20;
    h[uri.toString()] = {
      'title': title,
      'positionMs': complete ? 0 : position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'lastWatched': DateTime.now().toIso8601String(),
    };
    // Keep a bounded history to avoid growing preferences forever.
    if (h.length > 200) {
      final sorted = h.keys.toList()..sort((a, b) {
        final aDate = (h[a] as Map)['lastWatched'] as String? ?? '';
        final bDate = (h[b] as Map)['lastWatched'] as String? ?? '';
        return bDate.compareTo(aDate);
      });
      for (final key in sorted.skip(200)) { h.remove(key); }
    }
    await _prefs.setString('history', jsonEncode(h));
  }
  Future<List<WatchItem>> recent() async {
    final h = await _getHistory();
    final items = <WatchItem>[];
    for (final entry in h.entries) {
      try {
        final value = Map<String, dynamic>.from(entry.value as Map);
        items.add(WatchItem(
          uri: Uri.parse(entry.key),
          title: value['title'] as String? ?? entry.key,
          position: Duration(milliseconds: (value['positionMs'] as num? ?? 0).toInt()),
          duration: Duration(milliseconds: (value['durationMs'] as num? ?? 0).toInt()),
          lastWatched: value['lastWatched'] as String? ?? '',
        ));
      } catch (_) { /* ignore corrupt records */ }
    }
    items.sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return items;
  }
}

class WatchItem {
  const WatchItem({required this.uri, required this.title, required this.position, required this.duration, required this.lastWatched});
  final Uri uri;
  final String title;
  final Duration position;
  final Duration duration;
  final String lastWatched;
}
