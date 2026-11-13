import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/media_types.dart';
import '../services/mini_ipc.dart';
import '../services/sleep_timer.dart';

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
    player.stream.width.listen((w) {
      sourceWidth = w ?? 0;
      notifyListeners(); // the mini player window follows the picture's shape
    });
    player.stream.height.listen((h) {
      sourceHeight = h ?? 0;
      _applyQuality();
      notifyListeners();
    });
    player.stream.tracks.listen((_) => notifyListeners());
    player.stream.track.listen((_) => notifyListeners());
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

  /// Seconds jumped by the seek shortcuts / buttons.
  int seekStep = 5;
  int _speedIndex = 2;

  /// Chosen max height in px; 0 = Original, [qualityAuto] = Auto.
  int quality = 0;

  /// Auto quality: Original normally, [autoReducedHeight] while [reducedLoad].
  static const qualityAuto = -1;
  static const autoReducedHeight = 480;

  /// True while the picture is barely visible (minimized / mini player).
  bool reducedLoad = false;

  Future<void> setReducedLoad(bool v) async {
    if (reducedLoad == v) return;
    reducedLoad = v;
    if (quality == qualityAuto) await _applyQuality();
    notifyListeners();
  }

  /// Height of the current video in px (0 if unknown / audio).
  int sourceHeight = 0;

  /// Width of the current video in px (0 if unknown / audio).
  int sourceWidth = 0;

  /// Width / height of the current picture; 16:9 until it is known.
  double get videoAspect =>
      sourceWidth > 0 && sourceHeight > 0 ? sourceWidth / sourceHeight : 16 / 9;

  static const qualityHeights = [1080, 720, 480, 360];

  /// Options at or below the source height. Never offers an upscale.
  List<int> get qualityOptions => [
    0,
    qualityAuto,
    for (final h in qualityHeights)
      if (h <= sourceHeight) h,
  ];

  /// The height actually in effect (0 = Original).
  int get effectiveQuality {
    final target = quality == qualityAuto
        ? (reducedLoad ? autoReducedHeight : 0)
        : quality;
    return target != 0 && target < sourceHeight ? target : 0;
  }

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

  /// While a separate mini player is open it is the one playing: requests
  /// made in the main window are forwarded to it instead.
  RemotePlayback? remote;

  /// Stops playback later (set up by the main window only).
  SleepTimer? sleep;
  bool get _forwarding => remote?.active ?? false;

  /// Replaces the queue with [paths] and starts playing.
  Future<void> openPaths(List<String> paths, {int start = 0}) async {
    if (paths.isEmpty) return;
    if (_forwarding) return remote!.open(paths, start: start);
    await _load(paths, start, play: true);
  }

  Future<void> open(String path) => openPaths([path]);

  /// Waits until the current file's duration is known (it may already be).
  /// The duration stream is a broadcast stream, so an event that fired before
  /// we listen would be missed; poll the state instead.
  Future<bool> _waitForDuration([
    Duration timeout = const Duration(seconds: 5),
  ]) async {
    final deadline = DateTime.now().add(timeout);
    while (player.state.duration <= Duration.zero) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return true;
  }

  /// Opens [path] and jumps to [position] once the duration is known.
  Future<void> openAt(String path, Duration position) async {
    if (_forwarding) return remote!.open([path], at: position);
    await openPaths([path]);
    // If the duration cannot be read, playback just stays at the start.
    if (await _waitForDuration()) await player.seek(position);
  }

  /// What a mini player needs to carry on from here.
  Map<String, dynamic> snapshot() => {
    'queue': [for (final q in queue) q.path],
    'index': index,
    'posMs': player.state.position.inMilliseconds,
    'playing': player.state.playing,
    'volume': player.state.volume,
    'speed': speed,
  };

  /// Loads a queue at a position, as left by the other window. Not forwarded.
  Future<void> adoptState({
    required List<String> paths,
    required int index,
    required Duration position,
    required bool play,
  }) async {
    if (paths.isEmpty) return;
    await _load(paths, index, play: false);
    if (position > Duration.zero && await _waitForDuration()) {
      await player.seek(position);
    }
    if (play) await player.play();
  }

  Future<void> addPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    if (_forwarding) return remote!.add(paths);
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

  Future<void> next() async {
    if (_forwarding) return remote!.next();
    await player.next();
  }

  Future<void> previous() async {
    if (_forwarding) return remote!.previous();
    await player.previous();
  }

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

  // --- Audio / subtitle tracks ---

  static bool _real(String id) => id != 'auto' && id != 'no';

  /// Selectable audio tracks of the current file (excludes mpv's auto/no).
  List<AudioTrack> get audioTracks => [
    for (final t in player.state.tracks.audio)
      if (_real(t.id)) t,
  ];

  /// Selectable subtitle tracks (embedded and externally loaded).
  List<SubtitleTrack> get subtitleTracks => [
    for (final t in player.state.tracks.subtitle)
      if (_real(t.id)) t,
  ];

  AudioTrack get currentAudioTrack => player.state.track.audio;
  SubtitleTrack get currentSubtitleTrack => player.state.track.subtitle;

  /// True when subtitles are switched off.
  bool get subtitlesOff => currentSubtitleTrack.id == 'no';

  Future<void> setAudioTrack(AudioTrack t) => player.setAudioTrack(t);

  Future<void> setSubtitleTrack(SubtitleTrack t) => player.setSubtitleTrack(t);

  Future<void> disableSubtitles() =>
      player.setSubtitleTrack(SubtitleTrack.no());

  /// Loads an external subtitle file (.srt, .ass, ...) and selects it.
  Future<void> loadSubtitleFile(String path) => player.setSubtitleTrack(
    SubtitleTrack.uri(Uri.file(path).toString(), title: fileNameOf(path)),
  );

  /// Human-readable label for a track.
  static String trackLabel(String id, String? title, String? language) {
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
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
    // Private files are never written to the saved queue.
    final hide = isPrivate;
    final shown = [
      for (final q in queue)
        if (hide == null || !hide(q.path)) q.path,
    ];
    _prefs?.setStringList('queue', shown);
    _prefs?.setInt('queueIndex', shown.length == queue.length ? index : 0);
  }

  /// Tells which files are private (set by the app). They are kept out of the
  /// saved queue, and [dropPrivate] removes them when Private locks.
  bool Function(String path)? isPrivate;

  /// Stops playing private files and takes them out of the queue.
  Future<void> dropPrivate() async {
    final hide = isPrivate;
    if (hide == null || !queue.any((q) => hide(q.path))) return;
    await player.pause();
    for (var i = queue.length - 1; i >= 0; i--) {
      if (hide(queue[i].path)) await removeAt(i);
    }
    if (queue.isEmpty) await player.stop();
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_forwarding) return remote!.toggle();
    await player.playOrPause();
  }

  Future<void> seekRelative(Duration delta) async {
    final target = player.state.position + delta;
    final max = player.state.duration;
    await player.seek(
      target < Duration.zero ? Duration.zero : (target > max ? max : target),
    );
  }

  Future<void> setSpeed(double v) async {
    final i = speeds.indexOf(v);
    if (i < 0) return;
    _speedIndex = i;
    await player.setRate(v);
    notifyListeners();
  }

  Future<void> _setMpv(String name, String value) async {
    final platform = player.platform;
    if (platform is NativePlayer) await platform.setProperty(name, value);
  }

  /// Hardware decoding: 'auto' | 'on' | 'off'.
  Future<void> setHwdec(String mode) => _setMpv('hwdec', switch (mode) {
    'on' => 'auto',
    'off' => 'no',
    _ => 'auto-safe',
  });

  /// When false, playback pauses at the end of each file instead of moving on.
  Future<void> setAutoNext(bool on) =>
      _setMpv('keep-open', on ? 'no' : 'always');

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
