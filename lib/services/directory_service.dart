import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import '../models/media_entry.dart';

class DirectoryService {
  DirectoryService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<MediaEntry>> list(Uri directory) async {
    final response = await _client.get(directory).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $directory');
    }
    final doc = parser.parse(response.body);
    final results = <String, MediaEntry>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'];
      if (href == null || href.trim().isEmpty || href.startsWith('#') || href.startsWith('?')) continue;
      Uri candidate;
      try {
        candidate = directory.resolve(href);
      } catch (_) {
        continue;
      }
      if (candidate.scheme != directory.scheme || candidate.host != directory.host || candidate.port != directory.port) continue;
      // Ignore parent links and anything outside the current folder.
      if (!candidate.path.startsWith(directory.path) || candidate.path == directory.path) continue;
      final relative = candidate.path.substring(directory.path.length);
      final cleanRelative = relative.endsWith('/') ? relative.substring(0, relative.length - 1) : relative;
      if (cleanRelative.isEmpty || cleanRelative.contains('/')) continue;
      final isDir = candidate.path.endsWith('/') || href.endsWith('/');
      // Prefer the visible link label from the HTML directory listing.
      // Python http.server displays actual spaces there, even when href uses %20.
      // Fall back to decoding the URL segment if the label is empty or generic.
      final linkLabel = a.text.trim().replaceAll(RegExp(r'/$'), '');
      final title = linkLabel.isNotEmpty && linkLabel != '../' && linkLabel != '..'
          ? linkLabel
          : _decodeDisplayName(cleanRelative);
      final item = MediaEntry(title: title, uri: candidate.replace(query: '', fragment: ''), isDirectory: isDir);
      if (isDir || item.isVideo || item.isSubtitle) results[item.uri.toString()] = item;
    }
    final entries = results.values.toList();
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return _naturalCompare(a.title.toLowerCase(), b.title.toLowerCase());
    });
    return entries;
  }

  // Decode percent-escaped names only for display, never for the media URL.
  // A second pass accommodates links that were encoded twice (%2520 -> space).
  String _decodeDisplayName(String value) {
    var decoded = value;
    for (var i = 0; i < 2; i++) {
      if (!RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(decoded)) break;
      try {
        final next = Uri.decodeComponent(decoded);
        if (next == decoded) break;
        decoded = next;
      } on FormatException {
        break;
      }
    }
    return decoded;
  }

  // Natural order: Episode 2 before Episode 10.
  int _naturalCompare(String a, String b) {
    final regex = RegExp(r'\d+|\D+');
    final aa = regex.allMatches(a).map((m) => m.group(0)!).toList();
    final bb = regex.allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < aa.length && i < bb.length; i++) {
      final x = int.tryParse(aa[i]);
      final y = int.tryParse(bb[i]);
      final cmp = x != null && y != null ? x.compareTo(y) : aa[i].compareTo(bb[i]);
      if (cmp != 0) return cmp;
    }
    return aa.length.compareTo(bb.length);
  }

  void close() => _client.close();
}
