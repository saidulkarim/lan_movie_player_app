import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/media_entry.dart';
import '../services/preferences_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.videos, required this.initialIndex, required this.subtitles});
  final List<MediaEntry> videos;
  final int initialIndex;
  final List<MediaEntry> subtitles;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final _prefs = PreferencesService();
  final _listeners = <StreamSubscription<dynamic>>[];
  Timer? _hideTimer;
  Timer? _saveTimer;
  int _index = 0;
  int _mediaToken = 0;
  bool _visible = true;
  bool _locked = false;
  bool _playing = false;
  bool _buffering = true;
  bool _seeking = false;
  bool _opening = false;
  bool _canSeek = false;
  String? _seekNotice;
  bool _finished = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _seekPreview = Duration.zero;
  double _rate = 1;
  double _subtitleSize = 22;
  String? _error;
  SubtitleTrack? _externalSubtitle;

  MediaEntry get _current => widget.videos[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
    _controller = VideoController(_player);
    _listeners.addAll([
      _player.stream.position.listen((p) { if (mounted && !_seeking) setState(() => _position = p); }),
      _player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); }),
      _player.stream.playing.listen((p) { if (mounted) setState(() { _playing = p; if (p) _error = null; }); }),
      _player.stream.buffering.listen((b) { if (mounted) setState(() => _buffering = b); }),
      _player.stream.completed.listen((done) {
        if (done && !_finished && mounted && !_opening) {
          _finished = true;
          _saveCurrent(position: _duration);
          _showCompleted();
        }
      }),
      _player.stream.error.listen((e) {
        // mpv reports seekability notices on this stream. They are not playback failures.
        if (e.contains('force-seekable') || e.contains('not seekable')) {
          if (mounted) setState(() => _seekNotice = 'Server does not support seeking. Use the included range_server.py.');
          return;
        }
        if (mounted) setState(() => _error = e);
      }),
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _saveTimer = Timer.periodic(const Duration(seconds: 8), (_) => _saveCurrent());
    _openCurrent();
  }

  // Check for proper HTTP 206 support without downloading the entire movie.
  Future<bool> _supportsRange(Uri url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', url)
        ..headers['Range'] = 'bytes=0-0';
      final response = await client.send(request).timeout(const Duration(seconds: 8));
      final range = response.headers['content-range'] ?? '';
      final supported = response.statusCode == 206 && range.startsWith('bytes 0-0/');
      await response.stream.listen((_) {}).cancel();
      return supported;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _openCurrent() async {
    final token = ++_mediaToken;
    _finished = false;
    _opening = true;
    _externalSubtitle = null;
    _canSeek = false;
    _seekNotice = null;
    if (mounted) setState(() { _error = null; _position = Duration.zero; _duration = Duration.zero; _visible = true; });
    try {
      final rangeSupported = await _supportsRange(_current.uri);
      if (!mounted || token != _mediaToken) return;
      setState(() {
        _canSeek = rangeSupported;
        if (!rangeSupported) _seekNotice = 'Seeking unavailable: server needs HTTP byte-range support.';
      });
      await _player.open(Media(_current.uri.toString()), play: true);
      if (!mounted || token != _mediaToken) return;
      final stem = _current.stem.toLowerCase();
      final matches = widget.subtitles.where((s) => s.stem.toLowerCase() == stem).toList();
      if (matches.isNotEmpty) {
        final preferred = matches.firstWhere((s) => s.extension == '.srt', orElse: () => matches.first);
        _externalSubtitle = SubtitleTrack.uri(preferred.uri.toString(), title: preferred.title);
        try { await _player.setSubtitleTrack(_externalSubtitle!); } catch (_) { /* May require HTTP/codec support */ }
      }
      if (!mounted || token != _mediaToken) return;
      final saved = await _prefs.position(_current.uri);
      if (!mounted || token != _mediaToken) return;
      if (_canSeek && saved != null && saved.inSeconds >= 10) {
        // Seeking to a prior position may be delayed until media becomes seekable.
        await _player.seek(saved);
      }
      _opening = false;
      _scheduleHide();
    } catch (e) {
      _opening = false;
      if (mounted && token == _mediaToken) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveCurrent({Duration? position}) async {
    if (_opening || _duration <= Duration.zero) return;
    await _prefs.record(_current.uri, _current.title, position ?? _position, _duration);
  }

  Future<void> _switchEpisode(int next) async {
    if (next < 0 || next >= widget.videos.length || next == _index) return;
    await _saveCurrent();
    if (!mounted) return;
    setState(() => _index = next);
    await _openCurrent();
  }

  void _showCompleted() {
    if (!mounted) return;
    if (_index + 1 < widget.videos.length) {
      showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Episode finished'),
        content: Text('Play next: ${widget.videos[_index + 1].title}?'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { Navigator.pop(context); _switchEpisode(_index + 1); }, child: const Text('Play next'))],
      ));
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_visible && _playing && !_locked) {
      _hideTimer = Timer(const Duration(seconds: 4), () { if (mounted) setState(() => _visible = false); });
    }
  }

  void _toggleOverlay() { setState(() => _visible = !_visible); _scheduleHide(); }

  Future<void> _skip(int seconds) async {
    if (!_canSeek) return;
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await _player.seek(target);
    _scheduleHide();
  }

  Future<void> _chooseSubtitle() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks.subtitle;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Subtitles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ListTile(title: const Text('Off'), leading: const Icon(Icons.subtitles_off), onTap: () async { await _player.setSubtitleTrack(SubtitleTrack.no()); if (context.mounted) Navigator.pop(context); }),
        ListTile(title: const Text('Automatic'), leading: const Icon(Icons.auto_awesome), onTap: () async { await _player.setSubtitleTrack(SubtitleTrack.auto()); if (context.mounted) Navigator.pop(context); }),
        if (_externalSubtitle != null) ListTile(title: Text('External: ${_externalSubtitle!.title ?? 'subtitle'}'), leading: const Icon(Icons.closed_caption), onTap: () async { await _player.setSubtitleTrack(_externalSubtitle!); if (context.mounted) Navigator.pop(context); }),
        ...tracks.where((t) => t.id != 'auto' && t.id != 'no').map((t) => ListTile(
          title: Text(t.title ?? 'Track ${t.id}'), subtitle: Text(t.language ?? ''),
          leading: const Icon(Icons.subtitles),
          onTap: () async { await _player.setSubtitleTrack(t); if (context.mounted) Navigator.pop(context); },
        )),
        Row(children: [const Text('Subtitle size'), Expanded(child: Slider(min: 14, max: 40, divisions: 13, value: _subtitleSize, onChanged: (v) { setState(() => _subtitleSize = v); Navigator.pop(context); _chooseSubtitle(); }))]),
      ]),
    )));
    _scheduleHide();
  }

  Future<void> _chooseAudio() async {
    _hideTimer?.cancel();
    final tracks = _player.state.tracks.audio;
    await showModalBottomSheet<void>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(16), child: Text('Audio tracks', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
      ListTile(title: const Text('Automatic'), onTap: () async { await _player.setAudioTrack(AudioTrack.auto()); if (context.mounted) Navigator.pop(context); }),
      ...tracks.where((t) => t.id != 'auto' && t.id != 'no').map((t) => ListTile(
        title: Text(t.title ?? 'Track ${t.id}'), subtitle: Text(t.language ?? ''),
        onTap: () async { await _player.setAudioTrack(t); if (context.mounted) Navigator.pop(context); },
      )),
    ])));
    _scheduleHide();
  }

  Future<void> _chooseSpeed() async {
    _hideTimer?.cancel();
    await showModalBottomSheet<void>(context: context, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('Playback speed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      Wrap(spacing: 8, children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) => ChoiceChip(
        label: Text('${speed}x'), selected: _rate == speed,
        onSelected: (_) async { await _player.setRate(speed); if (mounted) setState(() => _rate = speed); if (context.mounted) Navigator.pop(context); },
      )).toList()), const SizedBox(height: 20),
    ])));
    _scheduleHide();
  }

  String _time(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  Widget _control(IconData icon, VoidCallback? onTap, {double size = 30, String? tooltip}) => IconButton(
    tooltip: tooltip, icon: Icon(icon, size: size), onPressed: onTap, color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    final totalMs = _duration.inMilliseconds;
    final progress = (_seeking ? _seekPreview.inMilliseconds : _position.inMilliseconds).toDouble().clamp(0.0, totalMs <= 0 ? 1.0 : totalMs.toDouble());
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Stack(fit: StackFit.expand, children: [
      Video(controller: _controller, controls: NoVideoControls,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          style: TextStyle(fontSize: _subtitleSize, color: Colors.white, backgroundColor: const Color(0x99000000), fontWeight: FontWeight.w600),
          padding: const EdgeInsets.only(bottom: 64),
        )),
      if (_buffering) const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      // Tap zones: left/right double-tap skip, center single-tap controls.
      Row(children: [
        Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleOverlay, onDoubleTap: () => _locked ? null : _skip(-10))),
        Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleOverlay, onDoubleTap: () { if (!_locked) _player.playOrPause(); })),
        Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleOverlay, onDoubleTap: () => _locked ? null : _skip(10))),
      ]),
      if (_locked)
        Positioned(top: 14, left: 12, child: _control(Icons.lock_open, () { setState(() => _locked = false); _scheduleHide(); }, tooltip: 'Unlock controls')),
      if (_visible && !_locked) ...[
        Positioned(top: 0, left: 0, right: 0, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
          child: Row(children: [
            _control(Icons.arrow_back, () => Navigator.pop(context), tooltip: 'Back'),
            Expanded(child: Text(_current.title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            _control(Icons.audiotrack, _chooseAudio, tooltip: 'Audio tracks'),
            _control(Icons.subtitles, _chooseSubtitle, tooltip: 'Subtitles'),
            _control(Icons.speed, _chooseSpeed, tooltip: 'Playback speed'),
            _control(Icons.lock_outline, () => setState(() { _locked = true; _visible = false; }), tooltip: 'Lock controls'),
          ]),
        )),
        Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
          _control(Icons.skip_previous, _index > 0 ? () => _switchEpisode(_index - 1) : null, size: 38),
          const SizedBox(width: 12),
          _control(Icons.replay_10, _canSeek ? () => _skip(-10) : null, size: 42),
          const SizedBox(width: 18),
          _control(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, _player.playOrPause, size: 62),
          const SizedBox(width: 18),
          _control(Icons.forward_10, _canSeek ? () => _skip(10) : null, size: 42),
          const SizedBox(width: 12),
          _control(Icons.skip_next, _index + 1 < widget.videos.length ? () => _switchEpisode(_index + 1) : null, size: 38),
        ])),
        Positioned(bottom: 0, left: 12, right: 12, child: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
          padding: const EdgeInsets.fromLTRB(10, 15, 10, 10),
          child: Row(children: [
            Text(_time(_seeking ? _seekPreview : _position), style: const TextStyle(color: Colors.white)),
            Expanded(child: Slider(
              onChanged: _canSeek ? (value) => setState(() => _seekPreview = Duration(milliseconds: value.toInt())) : null,
              activeColor: Colors.redAccent, min: 0, max: totalMs <= 0 ? 1 : totalMs.toDouble(), value: progress,
              onChangeStart: _canSeek ? (_) { _hideTimer?.cancel(); setState(() { _seeking = true; _seekPreview = _position; }); } : null,
              onChangeEnd: _canSeek ? (value) async { setState(() { _seeking = false; _position = Duration(milliseconds: value.toInt()); }); await _player.seek(_position); _scheduleHide(); } : null,
            )),
            Text(_time(_duration), style: const TextStyle(color: Colors.white)),
          ]),
        )),
      ],
      if (_seekNotice != null && _visible && _error == null)
        Positioned(top: 66, left: 16, right: 16,
          child: IgnorePointer(child: Text(_seekNotice!, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.amber, backgroundColor: Colors.black87)))),
      if (_error != null) Positioned.fill(child: Container(
        color: Colors.black87, alignment: Alignment.center, padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _openCurrent, child: const Text('Retry')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to library')),
        ]),
      )),
    ])));
  }

  @override
  void dispose() {
    _mediaToken++;
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    // Start async save before disposal; no widget state is accessed afterwards.
    _saveCurrent();
    for (final listener in _listeners) { listener.cancel(); }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }
}
