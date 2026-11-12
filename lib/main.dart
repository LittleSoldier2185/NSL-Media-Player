import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/legacy.dart';

import 'player_controller/player_controller.dart';
import 'services/app_mini_port.dart';
import 'services/history_service.dart';
import 'services/library_service.dart';
import 'services/mini_ipc.dart';
import 'services/playlist_service.dart';
import 'services/settings_service.dart';
import 'services/sleep_port.dart';
import 'services/sleep_timer.dart';
import 'services/smtc_service.dart';
import 'ui/player_page.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final settings = await AppSettings.load();

  // Started by the main window as the separate mini player? Then connect to it
  // first: it tells us what to play. If it cannot be reached, just quit.
  final miniArgs = parseMiniArgs(args);
  final miniChild = miniArgs == null ? null : await MiniChild.connect(miniArgs);
  if (miniArgs != null && miniChild == null) exit(1);

  final saved = miniChild == null && settings.rememberWindow
      ? settings.windowBounds
      : null;
  final options = miniChild != null
      ? const WindowOptions(
          size: Size(420, 248),
          minimumSize: Size(200, 100),
          center: false,
          title: 'NSL Mini',
          titleBarStyle: TitleBarStyle.hidden,
        )
      : WindowOptions(
          size: saved?.size ?? const Size(1280, 760),
          minimumSize: const Size(640, 420),
          center: saved == null,
          title: 'NSL Resonance',
          titleBarStyle: TitleBarStyle.hidden,
        );
  await windowManager.waitUntilReadyToShow(options, () async {
    // The mini player window is shown by the page once it has its size.
    if (miniChild != null) return;
    if (saved != null) await windowManager.setPosition(saved.topLeft);
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = NslPlayerController(settings.prefs);
  controller.seekStep = settings.seekStep;
  // The mini player process reports to the main window instead of writing
  // history (two processes must not both write the preferences file).
  final history = HistoryService(
    settings.prefs,
    controller,
    settings,
    miniChild == null,
  );
  final library = LibraryService(settings.prefs);
  final playlists = PlaylistService();
  final miniHost = miniChild == null
      ? MiniHost(AppMiniPort(controller, history, settings))
      : null;
  controller.remote = miniHost;
  if (miniChild == null) {
    controller.sleep = SleepTimer(
      ControllerSleepPort(controller),
      fade: () => Duration(seconds: settings.sleepFadeSeconds),
    );
  }
  runApp(
    NslApp(
      controller: controller,
      settings: settings,
      history: history,
      library: library,
      playlists: playlists,
      miniHost: miniHost,
      miniChild: miniChild,
      initialArgs: args,
    ),
  );
  _applyPlayerSettings(controller, settings, mini: miniChild != null);
  // Media keys belong to the main window only; started after the first frame
  // so a native failure cannot leave a blank window.
  if (miniChild == null) SmtcService.start(controller, settings);
}

/// Applies saved player options. Runs after the first frame is on screen and
/// never blocks startup: a failing native call must not leave a blank window.
Future<void> _applyPlayerSettings(
  NslPlayerController controller,
  AppSettings settings, {
  bool mini = false,
}) async {
  Future<void> safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('Could not apply a saved player setting: $e\n$st');
    }
  }

  // The mini player takes volume and speed from the main window instead, and
  // decides about video itself.
  final vol = settings.defaultVolume;
  if (!mini && vol != null) await safe(() => controller.setVolume(vol));
  if (!mini) await safe(() => controller.setSpeed(settings.defaultSpeed));
  await safe(() => controller.setHwdec(settings.hwdec));
  await safe(() => controller.setAutoNext(settings.autoNext));
  if (!mini && settings.audioOnlyDefault) {
    await safe(() => controller.setAudioOnly(true));
  }
}

class NslApp extends StatelessWidget {
  const NslApp({
    super.key,
    required this.controller,
    required this.settings,
    required this.history,
    required this.library,
    required this.playlists,
    required this.initialArgs,
    this.miniHost,
    this.miniChild,
  });

  final NslPlayerController controller;
  final AppSettings settings;
  final HistoryService history;
  final LibraryService library;
  final PlaylistService playlists;
  final MiniHost? miniHost;
  final MiniChild? miniChild;
  final List<String> initialArgs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'NSL Resonance',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: buildTheme(Brightness.light, settings.accent),
        darkTheme: buildTheme(Brightness.dark, settings.accent),
        home: PlayerPage(
          controller: controller,
          settings: settings,
          history: history,
          library: library,
          playlists: playlists,
          miniHost: miniHost,
          miniChild: miniChild,
          initialArgs: initialArgs,
        ),
      ),
    );
  }
}
