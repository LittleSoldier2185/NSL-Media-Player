import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/legacy.dart';

import 'player_controller/player_controller.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'ui/player_page.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final settings = await AppSettings.load();
  final saved = settings.rememberWindow ? settings.windowBounds : null;
  final options = WindowOptions(
    size: saved?.size ?? const Size(1280, 760),
    minimumSize: const Size(640, 420),
    center: saved == null,
    title: 'NSL Media Player',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (saved != null) await windowManager.setPosition(saved.topLeft);
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = NslPlayerController(settings.prefs);
  controller.seekStep = settings.seekStep;
  final history = HistoryService(settings.prefs, controller, settings);
  runApp(
    NslApp(
      controller: controller,
      settings: settings,
      history: history,
      initialArgs: args,
    ),
  );
  _applyPlayerSettings(controller, settings);
}

/// Applies saved player options. Runs after the first frame is on screen and
/// never blocks startup: a failing native call must not leave a blank window.
Future<void> _applyPlayerSettings(
  NslPlayerController controller,
  AppSettings settings,
) async {
  Future<void> safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('Could not apply a saved player setting: $e\n$st');
    }
  }

  final vol = settings.defaultVolume;
  if (vol != null) await safe(() => controller.setVolume(vol));
  await safe(() => controller.setSpeed(settings.defaultSpeed));
  await safe(() => controller.setHwdec(settings.hwdec));
  await safe(() => controller.setAutoNext(settings.autoNext));
}

class NslApp extends StatelessWidget {
  const NslApp({
    super.key,
    required this.controller,
    required this.settings,
    required this.history,
    required this.initialArgs,
  });

  final NslPlayerController controller;
  final AppSettings settings;
  final HistoryService history;
  final List<String> initialArgs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'NSL Media Player',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: buildTheme(Brightness.light, settings.accent),
        darkTheme: buildTheme(Brightness.dark, settings.accent),
        home: PlayerPage(
          controller: controller,
          settings: settings,
          history: history,
          initialArgs: initialArgs,
        ),
      ),
    );
  }
}
