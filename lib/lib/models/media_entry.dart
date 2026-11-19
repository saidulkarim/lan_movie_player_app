class MediaEntry {
  const MediaEntry({required this.title, required this.uri, required this.isDirectory});
  final String title;
  final Uri uri;
  final bool isDirectory;

  static const videoExtensions = {'.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v', '.ts', '.mpeg', '.mpg'};
  static const subtitleExtensions = {'.srt', '.ass', '.ssa', '.vtt', '.sub'};

  String get filename => uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? title;
  String get extension {
    final f = filename.toLowerCase();
    final i = f.lastIndexOf('.');
    return i < 0 ? '' : f.substring(i);
  }
  bool get isVideo => !isDirectory && videoExtensions.contains(extension);
  bool get isSubtitle => !isDirectory && subtitleExtensions.contains(extension);
  String get stem {
    final f = filename;
    final i = f.lastIndexOf('.');
    return i < 0 ? f : f.substring(0, i);
  }
}
