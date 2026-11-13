import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'media_types.dart';
import 'thumbnail_service.dart';

/// Converts [src] to a JPEG at [dst]; true when [dst] was written.
typedef HeicRun = Future<bool> Function(String src, String dst);

/// Flutter cannot decode HEIC/HEIF, so those pictures are converted to JPEG
/// first, using the decoder Windows already has (the "HEIF Image Extension"
/// from the Microsoft Store). The JPEG is cached in
/// `%APPDATA%\NSL Media Player\heic`, keyed like thumbnails (path + modified
/// time), so each picture is converted once. The original is never touched.
class HeicConverter {
  /// Both parameters are for tests.
  HeicConverter({Directory? dir, HeicRun? run})
    : _dirOverride = dir,
      _run = run ?? defaultRun;

  /// The converter the app uses.
  static final HeicConverter instance = HeicConverter();

  final Directory? _dirOverride;
  final HeicRun _run;
  final Map<String, Future<String?>> _inflight = {};
  Future<void> _queue = Future.value();

  static bool isHeic(String path) {
    final e = extensionOf(path);
    return e == 'heic' || e == 'heif';
  }

  Directory? get _dir {
    if (_dirOverride != null) return _dirOverride;
    final base = Platform.environment['APPDATA'];
    return base == null ? null : Directory('$base\\NSL Media Player\\heic');
  }

  File? _target(String path) {
    final d = _dir;
    if (d == null) return null;
    try {
      final modified = File(path).statSync().modified.millisecondsSinceEpoch;
      return File('${d.path}\\${ThumbnailService.keyFor(path, modified)}.jpg');
    } on Object {
      return null;
    }
  }

  /// Deletes the converted copy of [path], if there is one (used when a
  /// private picture is locked away).
  void forget(String path) {
    if (!isHeic(path)) return;
    try {
      final t = _target(path);
      if (t != null && t.existsSync()) t.deleteSync();
    } on Object {
      // a leftover cache file is harmless
    }
  }

  /// The converted JPEG when it already exists, else null (no conversion is
  /// started). For any other kind of picture this is [path] itself.
  String? cachedPath(String path) {
    if (!isHeic(path)) return path;
    final t = _target(path);
    return t != null && t.existsSync() && t.lengthSync() > 0 ? t.path : null;
  }

  /// A path Flutter can decode: [path] for ordinary pictures, the converted
  /// JPEG for HEIC. Null when the conversion is not possible (no HEIF
  /// extension, damaged file...).
  Future<String?> viewable(String path) {
    if (!isHeic(path)) return Future.value(path);
    final cached = cachedPath(path);
    if (cached != null) return Future.value(cached);
    final key = path.toLowerCase();
    return _inflight[key] ??= _convert(path).whenComplete(() {
      // A block body: returning the removed future would make it wait on itself.
      _inflight.remove(key);
    });
  }

  Future<String?> _convert(String path) {
    // One conversion at a time: each one starts a PowerShell process.
    final done = Completer<String?>();
    _queue = _queue.then((_) async {
      try {
        final t = _target(path);
        if (t == null) {
          done.complete(null);
          return;
        }
        final cached = cachedPath(path);
        if (cached != null) {
          done.complete(cached);
          return;
        }
        await t.parent.create(recursive: true);
        final part = '${t.path}.part';
        final ok = await _run(path, part);
        final f = File(part);
        if (ok && await f.exists() && await f.length() > 0) {
          await f.rename(t.path);
          done.complete(t.path);
        } else {
          if (await f.exists()) await f.delete();
          done.complete(null);
        }
      } on Object catch (e) {
        debugPrint('HEIC conversion failed: $e');
        if (!done.isCompleted) done.complete(null);
      }
    });
    return done.future;
  }

  /// Size of the converted pictures on disk.
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

  Future<void> clearCache() async {
    try {
      final d = _dir;
      if (d != null && await d.exists()) await d.delete(recursive: true);
    } on Object catch (e) {
      debugPrint('Could not clear converted pictures: $e');
    }
  }

  /// Decodes with WPF's imaging (which uses the Windows HEIF codec) and saves
  /// a JPEG. Paths travel in environment variables so no quoting can break.
  static Future<bool> defaultRun(String src, String dst) async {
    if (!Platform.isWindows) return false;
    const script = r'''
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore
$in = [IO.File]::OpenRead($env:NSL_SRC)
try {
  $dec = [Windows.Media.Imaging.BitmapDecoder]::Create($in, 'PreservePixelFormat', 'OnLoad')
  $enc = New-Object Windows.Media.Imaging.JpegBitmapEncoder
  $enc.QualityLevel = 92
  $enc.Frames.Add($dec.Frames[0])
  $out = [IO.File]::Create($env:NSL_DST)
  try { $enc.Save($out) } finally { $out.Dispose() }
} finally { $in.Dispose() }
''';
    try {
      final r = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-STA', '-Command', script],
        environment: {'NSL_SRC': src, 'NSL_DST': dst},
      ).timeout(const Duration(seconds: 60));
      if (r.exitCode != 0) debugPrint('HEIC conversion: ${r.stderr}');
      return r.exitCode == 0;
    } on Object catch (e) {
      debugPrint('HEIC conversion could not start: $e');
      return false;
    }
  }
}
