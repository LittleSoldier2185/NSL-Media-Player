import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/media_types.dart';

class QueueItem {
  QueueItem(this.path)
    : title = fileNameOf(path),
      isVideo = videoExtensions.contains(extensionOf(path));
  final String path;
  final String title;
  final bool isVideo;
}

enum NslRepeat { off, all, one }

enum QueueFilter { all, audio, video }

/// Wraps media_kit's [Player]: queue, shuffle/repeat, audio-only, persistence.
class NslPlayerController extends ChangeNotifier {
  NslPlayerController([this._prefs]) {
    video = VideoController(player);
    final v = _prefs?.getDouble('volume');
    if (v != null) player.setVolume(v);
    player.stream.volume.listen((v) {
      if (v > 0) _lastVolume = v;
      _prefs?.setDouble('volume', v);
    });
    quality = _prefs?.getInt('quality') ?? 0;
    player.stream.height.listen((h) {
      sourceHeight = h ?? 0;
      _applyQuality();
      notifyListeners();
    });
    player.stream.playlist.listen((pl) {
      if (pl.index != index) {
        index = pl.index;
        _saveQueue();
        notifyListeners();
      }
    });
  }

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  final SharedPreferences? _prefs;
  final Player player = Player();
  late final VideoController video;

  final List<QueueItem> queue = [];
  int index = 0;
  QueueFilter filter = QueueFilter.all;
  NslRepeat repeat = NslRepeat.off;
  bool shuffle = false;
  bool audioOnly = false;

  double _lastVolume = 100;
  int _speedIndex = 2;

  /// Chosen max height in px; 0 = Original.
  int quality = 0;

  /// Height of the current video in px (0 if unknown / audio).
  int sourceHeight = 0;

  static const qualityHeights = [1080, 720, 480, 360];

  /// Options at or below the source height. Never offers an upscale.
  List<int> get qualityOptions => [
    0,
    for (final h in qualityHeights)
      if (h <= sourceHeight) h,
  ];

  /// The height actually in effect (0 = Original).
  int get effectiveQuality =>
      quality != 0 && quality < sourceHeight ? quality : 0;

  Future<void> setQuality(int h) async {
    quality = h;
    _prefs?.setInt('quality', h);
    await _applyQuality();
    notifyListeners();
  }

  Future<void> _applyQuality() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final h = effectiveQuality;
    await platform.setProperty('vf', h == 0 ? '' : 'scale=-2:$h');
  }

  QueueItem? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;
  String? get currentPath => current?.path;
  String get title => current?.title ?? '';
  bool get isVideoFile => current?.isVideo ?? false;
  double get speed => speeds[_speedIndex];

  /// Whether to show the video surface (hidden for audio files / audio-only).
  bool get showVideo => current != null && isVideoFile && !audioOnly;

  List<MapEntry<int, QueueItem>> get filtered => [
    for (var i = 0; i < queue.length; i++)
      if (filter == QueueFilter.all ||
          (filter == QueueFilter.video) == queue[i].isVideo)
        MapEntry(i, queue[i]),
  ];

  /// Restores the last saved queue (paused).
  Future<void> restore() async {
    final saved = _prefs?.getStringList('queue') ?? const [];
    if (saved.isEmpty) return;
    await _load(saved, _prefs?.getInt('queueIndex') ?? 0, play: false);
  }

  Future<void> _load(
    List<String> paths,
    int start, {
    required bool play,
  }) async {
    queue
      ..clear()
      ..addAll(paths.map(QueueItem.new));
    index = start.clamp(0, queue.length - 1);
    await player.open(
      Playlist([for (final q in queue) Media(q.path)], index: index),
      play: play,
    );
    _saveQueue();
    notifyListeners();
  }

  /// Replaces the queue with [paths] and starts playing.
  Future<void> openPaths(List<String> paths, {int start = 0}) async {
    if (paths.isEmpty) return;
    await _load(paths, start, play: true);
  }

  Future<void> open(String path) => openPaths([path]);

  /// Opens [path] and jumps to [position] once the duration is known.
  Future<void> openAt(String path, Duration position) async {
    await openPaths([path]);
    try {
      await player.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));
      await player.seek(position);
    } on TimeoutException {
      // Could not read the duration; leave playback at the start.
    }
  }

  Future<void> addPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    if (queue.isEmpty) return openPaths(paths);
    for (final p in paths) {
      queue.add(QueueItem(p));
      await player.add(Media(p));
    }
    _saveQueue();
    notifyListeners();
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    await player.remove(i);
    _saveQueue();
    notifyListeners();
  }

  Future<void> playIndex(int i) => player.jump(i);
  Future<void> next() => player.next();
  Future<void> previous() => player.previous();

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    await player.setShuffle(shuffle);
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    repeat = NslRepeat.values[(repeat.index + 1) % NslRepeat.values.length];
    await player.setPlaylistMode(switch (repeat) {
      NslRepeat.off => PlaylistMode.none,
      NslRepeat.all => PlaylistMode.loop,
      NslRepeat.one => PlaylistMode.single,
    });
    notifyListeners();
  }

  void setFilter(QueueFilter f) {
    filter = f;
    notifyListeners();
  }

  /// Audio-only: stop decoding video (mpv `vid=no`) instead of just hiding it.
  Future<void> toggleAudioOnly() => setAudioOnly(!audioOnly);

  Future<void> setAudioOnly(bool value) async {
    if (audioOnly == value) return;
    audioOnly = value;
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('vid', audioOnly ? 'no' : 'auto');
    }
    notifyListeners();
  }

  void _saveQueue() {
    _prefs?.setStringList('queue', [for (final q in queue) q.path]);
    _prefs?.setInt('queueIndex', index);
  }

  Future<void> togglePlay() => player.playOrPause();

  Future<void> seekRelative(Duration delta) async {
    final target = player.state.position + delta;
    final max = player.state.duration;
    await player.seek(
      target < Duration.zero ? Duration.zero : (target > max ? max : target),
    );
  }

  Future<void> setVolume(double v) => player.setVolume(v.clamp(0, 100));

  Future<void> changeVolume(double delta) =>
      setVolume(player.state.volume + delta);

  Future<void> toggleMute() async {
    if (player.state.volume > 0) {
      await player.setVolume(0);
    } else {
      await player.setVolume(_lastVolume == 0 ? 100 : _lastVolume);
    }
  }

  Future<void> cycleSpeed() async {
    _speedIndex = (_speedIndex + 1) % speeds.length;
    await player.setRate(speed);
    notifyListeners();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
