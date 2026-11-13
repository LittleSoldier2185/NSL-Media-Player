import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'heic_converter.dart';
import 'media_types.dart';

/// Source of a full-size picture for a file (embedded cover, video frame...).
typedef RawImageSource = Future<Uint8List?> Function(String path);

/// Shrinks an encoded picture to thumbnail size and re-encodes it.
typedef Downscaler = Future<Uint8List?> Function(Uint8List bytes);

/// A pending thumbnail. Call [cancel] when the widget that asked for it goes
/// away so work for rows that were scrolled past is skipped.
class ThumbTicket {
  ThumbTicket._(this.future, this._cancel);
  final Future<Uint8List?> future;
  final VoidCallback _cancel;
  void cancel() => _cancel();
}

class _Job {
  _Job(this.key, this.run) : seq = _nextSeq++;
  static int _nextSeq = 0;

  /// Order of the request. The pool starts the highest first, whatever order
  /// the jobs happen to reach it in (disk lookups finish in any order).
  final int seq;
  final String key;
  final Future<Uint8List?> Function() run;
  final Completer<Uint8List?> done = Completer();
  int refs = 0;
  bool started = false;
  bool cancelled = false;
}

/// Runs up to [maxConcurrent] jobs, newest request first: what the user is
/// looking at now matters more than what they scrolled past.
class _Pool {
  _Pool(this.maxConcurrent);
  final int maxConcurrent;
  final List<_Job> _stack = [];
  int _running = 0;

  void add(_Job j) {
    _stack.add(j);
    _pump();
  }

  void _pump() {
    while (_running < maxConcurrent && _stack.isNotEmpty) {
      var best = 0;
      for (var i = 1; i < _stack.length; i++) {
        if (_stack[i].seq > _stack[best].seq) best = i;
      }
      final j = _stack.removeAt(best);
      if (j.cancelled) {
        if (!j.done.isCompleted) j.done.complete(null);
        continue;
      }
      j.started = true;
      _running++;
      j
          .run()
          .then(
            (v) {
              if (!j.done.isCompleted) j.done.complete(v);
            },
            onError: (Object _) {
              if (!j.done.isCompleted) j.done.complete(null);
            },
          )
          .whenComplete(() {
            _running--;
            _pump();
          });
    }
  }
}

/// Small preview pictures for library files: embedded cover art (or a
/// `cover.jpg` / `folder.jpg` next to the file) for music, and a frame taken
/// a little way into the video for videos.
///
/// Results are cached in memory and on disk (`%APPDATA%\NSL Media Player\thumbs`)
/// so each file is only processed once until it changes.
class ThumbnailService {
  /// All parameters are for tests; the defaults do the real work.
  ThumbnailService({
    Directory? dir,
    RawImageSource? videoFrame,
    RawImageSource? audioArt,
    RawImageSource? image,
    Downscaler? downscale,
  }) : _dirOverride = dir,
       _videoFrame = videoFrame ?? defaultVideoFrame,
       _audioArt = audioArt ?? defaultAudioArt,
       _image = image ?? defaultImage,
       _downscale = downscale ?? defaultDownscale;

  static const thumbWidth = 256;
  static const _memoryLimit = 400;

  final Directory? _dirOverride;
  final RawImageSource _videoFrame;
  final RawImageSource _audioArt;
  final RawImageSource _image;
  final Downscaler _downscale;

  // Music extraction is cheap and runs in isolates; video needs a decoder
  // instance each, so they go one at a time.
  final _audioPool = _Pool(3);
  final _videoPool = _Pool(1);
  final Map<String, _Job> _inflight = {};

  /// Insertion order doubles as LRU order. A null value means "no picture".
  final LinkedHashMap<String, Uint8List?> _mem = LinkedHashMap();

  Directory? get _dir {
    if (_dirOverride != null) return _dirOverride;
    final base = Platform.environment['APPDATA'];
    return base == null ? null : Directory('$base\\NSL Media Player\\thumbs');
  }

  /// Stable key from the path and the file's modification time, so an edited
  /// file gets a fresh thumbnail.
  static String keyFor(String path, int modified) {
    var h = 0xcbf29ce484222325; // FNV-1a, 64 bit
    for (final u in path.toLowerCase().codeUnits) {
      h ^= u;
      h *= 0x100000001b3;
    }
    // Two 32-bit halves: a negative int must not turn into "-abc..." names.
    final hi = ((h >>> 32) & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final lo = (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '$hi$lo'
        '_$modified';
  }

  /// Asks for the thumbnail of [path] (whose modification time is [modified]).
  /// The future completes with PNG bytes, or null when the file has no picture.
  ThumbTicket request(String path, int modified) {
    final key = keyFor(path, modified);
    if (_mem.containsKey(key)) {
      final v = _mem.remove(key);
      _mem[key] = v;
      return ThumbTicket._(Future.value(v), () {});
    }
    var job = _inflight[key];
    if (job == null) {
      final isVideo = videoExtensions.contains(extensionOf(path));
      final j = _Job(key, () => _generate(path, key));
      job = j;
      _inflight[key] = j;
      unawaited(_start(j, path, isVideo));
      j.done.future.whenComplete(() {
        if (identical(_inflight[key], j)) _inflight.remove(key);
      });
    }
    job.refs++;
    final j = job;
    var cancelled = false;
    return ThumbTicket._(j.done.future, () {
      if (cancelled) return;
      cancelled = true;
      j.refs--;
      if (j.refs <= 0 && !j.started) {
        j.cancelled = true;
        if (identical(_inflight[j.key], j)) _inflight.remove(j.key);
      }
    });
  }

  Future<void> _start(_Job j, String path, bool isVideo) async {
    // Disk hits are quick, so they skip the (slow) generation queue.
    final cached = await _readDisk(j.key);
    if (cached != null) {
      _remember(j.key, cached.isEmpty ? null : cached);
      if (!j.done.isCompleted) j.done.complete(cached.isEmpty ? null : cached);
      return;
    }
    (isVideo ? _videoPool : _audioPool).add(j);
  }

  Future<Uint8List?> _generate(String path, String key) async {
    Uint8List? thumb;
    try {
      final raw = videoExtensions.contains(extensionOf(path))
          ? await _videoFrame(path)
          : kindOf(path) == MediaKind.image
          ? await _image(path)
          : await _audioArt(path);
      if (raw != null && raw.isNotEmpty) thumb = await _downscale(raw);
    } on Object catch (e) {
      debugPrint('Thumbnail failed: $e');
    }
    _remember(key, thumb);
    // An empty file records "no picture" so it is not retried every launch.
    await _writeDisk(key, thumb ?? Uint8List(0));
    return thumb;
  }

  void _remember(String key, Uint8List? v) {
    _mem.remove(key);
    _mem[key] = v;
    while (_mem.length > _memoryLimit) {
      _mem.remove(_mem.keys.first);
    }
  }

  File? _fileFor(String key) {
    final d = _dir;
    return d == null ? null : File('${d.path}\\$key.png');
  }

  Future<Uint8List?> _readDisk(String key) async {
    try {
      final f = _fileFor(key);
      if (f == null || !await f.exists()) return null;
      return await f.readAsBytes();
    } on Object {
      return null;
    }
  }

  Future<void> _writeDisk(String key, Uint8List bytes) async {
    try {
      final d = _dir;
      if (d == null) return;
      await d.create(recursive: true);
      await _fileFor(key)!.writeAsBytes(bytes);
    } on Object catch (e) {
      debugPrint('Could not cache thumbnail: $e');
    }
  }

  // ---- cache management ----

  Future<int> cacheSizeBytes() async {
    var total = 0;
    try {
      final d = _dir;
      if (d == null || !await d.exists()) return 0;
      await for (final e in d.list()) {
        if (e is File) total += await e.length();
      }
    } on Object {
      // report what we counted
    }
    return total;
  }

  /// Deletes all cached thumbnails; they are rebuilt as rows come into view.
  Future<void> clearCache() async {
    _mem.clear();
    try {
      final d = _dir;
      if (d != null && await d.exists()) await d.delete(recursive: true);
    } on Object catch (e) {
      debugPrint('Could not clear thumbnails: $e');
    }
  }

  // ---- real image sources ----

  /// Cover art embedded in the audio file, else a picture in its folder.
  static Future<Uint8List?> defaultAudioArt(String path) async {
    try {
      final embedded = await Isolate.run(() {
        final m = readMetadata(File(path), getImage: true);
        return m.pictures.isEmpty ? null : m.pictures.first.bytes;
      });
      if (embedded != null && embedded.isNotEmpty) return embedded;
    } on Object {
      // no readable tags: fall back to folder art
    }
    return folderArt(path);
  }

  /// The picture file itself (HEIC is converted to JPEG first). The decoder
  /// shrinks it while decoding, so a big photo is not held in memory whole.
  static Future<Uint8List?> defaultImage(String path) async {
    final readable = await HeicConverter.instance.viewable(path);
    return readable == null ? null : File(readable).readAsBytes();
  }

  /// A `cover` / `folder` / `front` / `album` picture beside [path], if any.
  static Future<Uint8List?> folderArt(String path) async {
    const names = {
      'cover',
      'folder',
      'front',
      'album',
      'albumart',
      'albumartsmall',
    };
    const exts = {'jpg', 'jpeg', 'png'};
    try {
      await for (final e in File(path).parent.list(followLinks: false)) {
        if (e is! File) continue;
        final n = fileNameOf(e.path).toLowerCase();
        final dot = n.lastIndexOf('.');
        if (dot > 0 &&
            exts.contains(n.substring(dot + 1)) &&
            names.contains(n.substring(0, dot))) {
          return await e.readAsBytes();
        }
      }
    } on Object {
      // unreadable folder
    }
    return null;
  }

  /// A frame 10% into the video, grabbed with a headless player. media_kit
  /// leaves video decoding off unless a VideoController asks for it, so
  /// `vid=auto` is set by hand.
  static Future<Uint8List?> defaultVideoFrame(String path) async {
    final player = Player();
    try {
      final native = player.platform;
      if (native is! NativePlayer) return null;
      await native.setProperty('vid', 'auto');
      await native.setProperty('ao', 'null'); // no sound device needed
      await player.open(Media(path), play: true);
      // Poll the state: the broadcast streams may already have fired.
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while ((player.state.width ?? 0) == 0 ||
          player.state.duration == Duration.zero) {
        if (DateTime.now().isAfter(deadline)) return null;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final duration = player.state.duration;
      await player.pause();
      await player.seek(duration * 0.1);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 10));
    } on Object {
      return null;
    } finally {
      await player.dispose();
    }
  }

  /// Decodes at [thumbWidth] pixels wide and re-encodes as PNG.
  static Future<Uint8List?> defaultDownscale(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: thumbWidth);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      return data?.buffer.asUint8List();
    } on Object {
      return null; // not a decodable picture
    } finally {
      codec?.dispose();
    }
  }
}
