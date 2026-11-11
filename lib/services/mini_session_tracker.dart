/// Measures what was watched in a mini player process, so the main window can
/// add it to the history when the mini player hands playback back.
class MiniSessionTracker {
  MiniSessionTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, _Acc> _items = {}; // insertion order = order played
  String? _path;
  bool _playing = false;
  DateTime? _since;

  /// The file being played changed. [countPlay] is false for the file the
  /// main window had already counted when it handed over.
  void trackChanged(String? path, {bool countPlay = true}) {
    _flush();
    _path = path;
    if (path != null) {
      final a = _items.putIfAbsent(path, _Acc.new);
      if (countPlay) a.plays++;
    }
    _restart();
  }

  void playingChanged(bool playing) {
    _flush();
    _playing = playing;
    _restart();
  }

  /// Latest position / length of the current file.
  void progress(int posMs, int durMs) {
    final a = _items[_path];
    if (a == null) return;
    a.posMs = posMs;
    if (durMs > 0) a.durMs = durMs;
  }

  /// One entry per file played: `path`, `seconds` watched, `posMs`, `durMs`
  /// and `plays` (how many times it was started).
  List<Map<String, dynamic>> results() {
    _flush();
    _restart();
    return [
      for (final e in _items.entries)
        if (e.value.seconds > 0 || e.value.plays > 0)
          {
            'path': e.key,
            'seconds': e.value.seconds,
            'posMs': e.value.posMs,
            'durMs': e.value.durMs,
            'plays': e.value.plays,
          },
    ];
  }

  void _flush() {
    final since = _since;
    final path = _path;
    if (since != null && path != null) {
      final ms = _now().difference(since).inMilliseconds;
      if (ms > 0) _items[path]!.seconds += ms / 1000;
    }
    _since = null;
  }

  void _restart() => _since = _playing && _path != null ? _now() : null;
}

class _Acc {
  double seconds = 0;
  int posMs = 0;
  int durMs = 0;
  int plays = 0;
}
