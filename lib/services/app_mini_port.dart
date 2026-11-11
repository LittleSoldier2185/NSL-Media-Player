import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/legacy.dart';

import '../player_controller/player_controller.dart';
import 'history_service.dart';
import 'mini_ipc.dart';
import 'settings_service.dart';

/// Connects the mini player host to the real app: the player controller, the
/// history, the preferences and the window.
class AppMiniPort implements MiniHostPort {
  AppMiniPort(this.controller, this.history, this.settings);

  final NslPlayerController controller;
  final HistoryService history;
  final AppSettings settings;

  @override
  Json pauseAndSnapshot() {
    final snapshot = controller.snapshot();
    unawaited(controller.player.pause());
    return snapshot;
  }

  @override
  Future<void> adopt(Json state, {required bool play}) async {
    final queue = state['queue'];
    if (queue is! List || queue.isEmpty) return;
    try {
      // Same file it already counted: it must not count as another play.
      await history.withoutCountingPlays(
        () => controller.adoptState(
          paths: [for (final p in queue) '$p'],
          index: state['index'] is int ? state['index'] as int : 0,
          position: Duration(
            milliseconds: state['posMs'] is int ? state['posMs'] as int : 0,
          ),
          play: play,
        ),
      );
      if (state['volume'] is num) {
        await controller.setVolume((state['volume'] as num).toDouble());
      }
      if (state['speed'] is num) {
        await controller.setSpeed((state['speed'] as num).toDouble());
      }
    } on Object catch (e) {
      debugPrint('Could not take playback back from the mini player: $e');
    }
  }

  @override
  void applyPrefs(Json prefs) {
    for (final e in prefs.entries) {
      final v = e.value;
      if (v != null) settings.put(e.key, v);
    }
  }

  @override
  void recordHistory(List<Json> entries) => history.recordExternal(entries);

  @override
  void bringToFront() {
    unawaited(() async {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    }());
  }

  @override
  void resumeLocal(Json snapshot) {
    if (snapshot['playing'] == true) unawaited(controller.player.play());
  }
}
