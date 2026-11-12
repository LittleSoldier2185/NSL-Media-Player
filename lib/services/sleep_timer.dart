import 'dart:async';

import 'package:flutter/foundation.dart';

/// What the sleep timer needs from the player.
abstract class SleepPort {
  /// Current volume, 0-100.
  double get volume;
  Future<void> setVolume(double v);
  Future<void> pause();

  /// Time left in the file being played, or null when it is not known (for
  /// example while the mini player in its own window is playing).
  Duration? get remainingInItem;

  /// Whether the volume can be faded (false when another window plays).
  bool get canFade;
}

enum SleepMode { off, countdown, clock, endOfItem }

/// Stops (pauses) playback later: after a countdown, at a clock time, or when
/// the file that is playing ends. The volume fades out first, then the player
/// pauses and the volume is put back, so the next play is not silent.
///
/// The target is a [DateTime] compared with the clock, not a tick counter, so
/// the timer stays right when the computer sleeps or the time is adjusted.
class SleepTimer extends ChangeNotifier {
  SleepTimer(
    this._port, {
    DateTime Function()? now,
    Duration tick = const Duration(milliseconds: 250),
    Duration Function()? fade,
  }) : _now = now ?? DateTime.now,
       _tick = tick,
       _fade = fade ?? (() => const Duration(seconds: 10));

  final SleepPort _port;
  final DateTime Function() _now;
  final Duration _tick;
  final Duration Function() _fade;

  SleepMode _mode = SleepMode.off;
  DateTime? _deadline;
  Timer? _timer;
  double? _baseVolume; // volume before the fade started

  SleepMode get mode => _mode;
  bool get active => _mode != SleepMode.off;

  /// When it will stop; null for "end of file" and when off.
  DateTime? get deadline => _deadline;

  /// Time until it stops, or null when off / waiting for the end of the file.
  Duration? get remaining {
    final d = _deadline;
    if (d == null) return null;
    final r = d.difference(_now());
    return r.isNegative ? Duration.zero : r;
  }

  void startCountdown(Duration d) {
    if (d <= Duration.zero) return cancel();
    _begin(SleepMode.countdown, _now().add(d));
  }

  /// Stops at [hour]:[minute] — today if that is still ahead, otherwise
  /// tomorrow.
  void startAt(int hour, int minute) {
    final n = _now();
    var t = DateTime(n.year, n.month, n.day, hour, minute);
    if (!t.isAfter(n)) t = DateTime(n.year, n.month, n.day + 1, hour, minute);
    _begin(SleepMode.clock, t);
  }

  void startEndOfItem() => _begin(SleepMode.endOfItem, null);

  void cancel() {
    final wasFading = _baseVolume != null;
    _stopTimer();
    _mode = SleepMode.off;
    _deadline = null;
    if (wasFading) _restoreVolume();
    notifyListeners();
  }

  void _begin(SleepMode m, DateTime? deadline) {
    if (_baseVolume != null) _restoreVolume();
    _mode = m;
    _deadline = deadline;
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => check());
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _restoreVolume() {
    final v = _baseVolume;
    _baseVolume = null;
    if (v != null) _port.setVolume(v);
  }

  /// One step of the timer; public so tests can drive it without waiting.
  Future<void> check() async {
    if (!active) return;
    final left = _mode == SleepMode.endOfItem
        ? _port.remainingInItem
        : remaining;
    if (left == null) {
      // Nothing known to wait for (e.g. nothing playing): keep waiting.
      notifyListeners();
      return;
    }
    final fade = _port.canFade ? _fade() : Duration.zero;
    if (left <= _stopMargin) {
      await _finish();
      return;
    }
    if (fade > Duration.zero && left <= fade) {
      _baseVolume ??= _port.volume;
      final f = left.inMilliseconds / fade.inMilliseconds;
      await _port.setVolume(_baseVolume! * f);
    }
    notifyListeners();
  }

  // Stopping a hair before the real end of a file (one default tick plus a
  // little) avoids the next file starting in the gap between two ticks.
  Duration get _stopMargin => _mode == SleepMode.endOfItem
      ? const Duration(milliseconds: 350)
      : Duration.zero;

  Future<void> _finish() async {
    _stopTimer();
    _mode = SleepMode.off;
    _deadline = null;
    await _port.pause();
    _restoreVolume();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
