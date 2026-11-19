import 'package:flutter/material.dart';
import '../models/media_entry.dart';
import '../services/directory_service.dart';
import '../services/preferences_service.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _directory = DirectoryService();
  final _settings = PreferencesService();
  final _search = TextEditingController();
  final _stack = <Uri>[];
  String _server = '';
  List<MediaEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;

  Uri get _current => _stack.last;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final url = await _settings.getServer();
    if (!mounted) return;
    _server = url;
    _stack.add(Uri.parse(url));
    await _load();
  }

  Future<void> _load() async {
    if (_stack.isEmpty) return;
    final token = ++_loadToken;
    setState(() { _loading = true; _error = null; _search.clear(); });
    try {
      final items = await _directory.list(_current);
      if (!mounted || token != _loadToken) return;
      setState(() { _entries = items; _loading = false; });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openFolder(Uri uri) {
    _stack.add(uri);
    _load();
  }

  void _backFolder() {
    if (_stack.length > 1) { _stack.removeLast(); _load(); }
  }

  Future<void> _configureServer() async {
    final controller = TextEditingController(text: _server);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your LAN server address (HTTP or HTTPS).'),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final value = controller.text.trim();
            final uri = Uri.tryParse(value);
            if (uri == null || !uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme)) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a valid http:// or https:// URL')));
              return;
            }
            Navigator.pop(ctx, uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/', query: '', fragment: '').toString());
          }, child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (newUrl == null || !mounted) return;
    await _settings.setServer(newUrl);
    if (!mounted) return;
    _server = newUrl;
    _stack..clear()..add(Uri.parse(newUrl));
    await _load();
  }

  Future<void> _showRecent() async {
    final recent = await _settings.recent();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Continue watching')),
      body: recent.isEmpty ? const Center(child: Text('No playback history yet')) : ListView.builder(
        itemCount: recent.length,
        itemBuilder: (ctx, index) {
          final item = recent[index];
          return ListTile(
            leading: const Icon(Icons.history, color: Colors.redAccent),
            title: Text(item.title, maxLines: 2),
            subtitle: item.duration.inSeconds > 0 ? LinearProgressIndicator(value: (item.position.inMilliseconds / item.duration.inMilliseconds).clamp(0.0, 1.0)) : null,
            onTap: () => Navigator.push(ctx, MaterialPageRoute<void>(builder: (_) => PlayerScreen(
              videos: [MediaEntry(title: item.title, uri: item.uri, isDirectory: false)], initialIndex: 0,
              subtitles: const [],
            ))),
          );
        },
      ),
    )));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase().trim();
    final display = _entries.where((e) => !e.isSubtitle && e.title.toLowerCase().contains(query)).toList();
    final videos = _entries.where((e) => e.isVideo).toList();
    final subs = _entries.where((e) => e.isSubtitle).toList();
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _backFolder(); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LAN Movie Player', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(tooltip: 'Continue watching', icon: const Icon(Icons.history), onPressed: _showRecent),
            IconButton(tooltip: 'Server settings', icon: const Icon(Icons.settings_ethernet), onPressed: _configureServer),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: Column(children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xff1e2230), borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.wifi, color: Colors.greenAccent, size: 18), SizedBox(width: 8), Text('INTRANET LIBRARY', style: TextStyle(fontSize: 12, letterSpacing: 1.6, color: Colors.white70))]),
              const SizedBox(height: 8),
              Text(_stack.isEmpty ? 'Connecting...' : _current.toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ]),
          ),
          if (_stack.length > 1)
            ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Parent folder'), onTap: _backFolder),
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: TextField(
            controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: 'Search this folder...', prefixIcon: const Icon(Icons.search),
              filled: true, fillColor: const Color(0xff1e2230), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
          )),
          Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
              : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.wifi_off, size: 54, color: Colors.redAccent), const SizedBox(height: 14),
                Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ])))
              : display.isEmpty ? const Center(child: Text('No video files or folders found'))
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  itemCount: display.length, padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                  itemBuilder: (ctx, index) {
                    final entry = display[index];
                    return Card(child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      leading: Icon(entry.isDirectory ? Icons.folder_rounded : Icons.play_circle_fill_rounded,
                        color: entry.isDirectory ? Colors.amber : Colors.redAccent, size: 40),
                      title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(entry.isDirectory ? 'Folder' : entry.extension.toUpperCase().replaceAll('.', '')),
                      trailing: Icon(entry.isDirectory ? Icons.chevron_right : Icons.play_arrow),
                      onTap: () => entry.isDirectory ? _openFolder(entry.uri) : Navigator.push(context, MaterialPageRoute<void>(
                        builder: (_) => PlayerScreen(videos: videos, initialIndex: videos.indexWhere((e) => e.uri == entry.uri), subtitles: subs),
                      )).then((_) { if (mounted) setState(() {}); }),
                    ));
                  },
                )),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() { _loadToken++; _directory.close(); _search.dispose(); super.dispose(); }
}
