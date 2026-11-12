import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../player_controller/player_controller.dart';
import 'settings_service.dart';

/// Windows media controls (SMTC): the hardware media keys and the volume
/// flyout / lock screen panel show the current title and drive the player.
///
/// Only the main window uses it. While the separate mini player owns playback
/// (`controller.remote.active`) the panel is switched off, so it never shows
/// the paused main window.
class SmtcService {
  SmtcService._(this._controller, this._settings, this._smtc) {
    final pl = _controller.player;
    _subs.add(pl.stream.playing.listen((_) => _sync()));
    _subs.add(pl.stream.duration.listen((_) => _sync()));
    _subs.add(pl.stream.position.listen(_onPosition));
    _subs.add(_smtc.buttonPressStream.listen(_onButton));
    _controller.addListener(_sync);
    _settings.addListener(_sync);
    _sync();
  }

  final NslPlayerController _controller;
  final AppSettings _settings;
  final SMTCWindows _smtc;
  final _subs = <StreamSubscription<Object?>>[];

  bool _enabled = true;
  String? _shownTitle;
  DateTime _lastTimeline = DateTime.fromMillisecondsSinceEpoch(0);

  /// Null when the native side is unavailable; the app then simply has no
  /// media-key support instead of failing.
  static Future<SmtcService?> start(
    NslPlayerController controller,
    AppSettings settings,
  ) async {
    try {
      await SMTCWindows.initialize();
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          stopEnabled: false,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
        enabled: settings.smtcEnabled,
      );
      return SmtcService._(controller, settings, smtc);
    } catch (e, st) {
      debugPrint('Windows media controls are not available: $e\n$st');
      return null;
    }
  }

  void _onButton(PressedButton b) {
    final pl = _controller.player;
    switch (b) {
      case PressedButton.play:
        if (!pl.state.playing) _controller.togglePlay();
      case PressedButton.pause:
        if (pl.state.playing) _controller.togglePlay();
      case PressedButton.next:
        _controller.next();
      case PressedButton.previous:
        _controller.previous();
      default:
        break;
    }
  }

  bool get _wanted =>
      _settings.smtcEnabled && !(_controller.remote?.active ?? false);

  void _sync() {
    try {
      final want = _wanted;
      if (want != _enabled) {
        _enabled = want;
        want ? _smtc.enableSmtc() : _smtc.disableSmtc();
      }
      if (!want) return;

      final title = _controller.current == null ? null : _controller.title;
      if (title != _shownTitle) {
        _shownTitle = title;
        if (title == null) {
          _smtc.clearMetadata();
        } else {
          _smtc.updateMetadata(MusicMetadata(title: title));
        }
      }
      final st = _controller.player.state;
      _smtc.setPlaybackStatus(
        title == null
            ? PlaybackStatus.stopped
            : st.playing
            ? PlaybackStatus.playing
            : PlaybackStatus.paused,
      );
      _pushTimeline(st.position, st.duration);
    } catch (e) {
      debugPrint('SMTC update failed: $e');
    }
  }

  void _onPosition(Duration pos) {
    // The panel animates its own progress, so twice a second is plenty.
    final now = DateTime.now();
    if (now.difference(_lastTimeline).inMilliseconds < 500) return;
    if (!_enabled) return;
    try {
      _pushTimeline(pos, _controller.player.state.duration);
    } catch (_) {}
  }

  void _pushTimeline(Duration pos, Duration dur) {
    _lastTimeline = DateTime.now();
    _smtc.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: dur.inMilliseconds,
        positionMs: pos.inMilliseconds.clamp(0, dur.inMilliseconds),
      ),
    );
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _controller.removeListener(_sync);
    _settings.removeListener(_sync);
    await _smtc.dispose();
  }
}
