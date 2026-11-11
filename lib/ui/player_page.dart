import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/legacy.dart';

import '../player_controller/player_controller.dart';
import '../services/media_types.dart';
import '../services/settings_service.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import 'home_page.dart';
import 'mini_player.dart';
import 'music_view.dart';
import 'queue_panel.dart';
import 'settings_page.dart';
import 'controls.dart';
import 'theme.dart';
import 'title_bar.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.controller,
    required this.settings,
    required this.history,
    required this.library,
    required this.initialArgs,
  });

  final NslPlayerController controller;
  final AppSettings settings;
  final HistoryService history;
  final LibraryService library;
  final List<String> initialArgs;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WindowListener {
  bool _fullscreen = false;
  bool _dragging = false;
  bool _showQueue = true;
  bool _settingsOpen = false;

  void _openSettings() => setState(() => _settingsOpen = true);

  /// Showing the Home / Dashboard instead of the player.
  late bool _home = !widget.initialArgs.any(isSupportedMedia);

  /// True when audio-only was switched on by minimizing (not by the user).
  bool _autoAudioOnly = false;

  // Mini player state
  bool _mini = false;
  bool _miniAudioOnly = false; // audio-only switched on by entering mini
  Rect? _fullBounds;
  static const _miniSize = Size(420, 248);

  NslPlayerController get c => widget.controller;
  AppSettings get s => widget.settings;

  Future<void> _enterMini() async {
    if (_mini) return;
    if (_fullscreen) await _toggleFullscreen(false);
    _fullBounds = await windowManager.getBounds();
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    // Set first so the resize events below are not saved as the full-window size.
    setState(() => _mini = true);
    // Resize while the window is still resizable: Windows ignores setSize
    // once resizing is disabled, which left the mini card in a stale layout.
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(_miniSize);
    await windowManager.setMaximumSize(_miniSize);
    final pos = s.miniRememberPos ? s.miniPosition : null;
    await windowManager.setBounds(
      Rect.fromLTWH(
        pos?.dx ?? _fullBounds!.left,
        pos?.dy ?? _fullBounds!.top,
        _miniSize.width,
        _miniSize.height,
      ),
    );
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(s.miniOnTop);
    await windowManager.setOpacity(s.miniOpacity / 100);
    c.setReducedLoad(true);
    // Mini + audio-only is the lightest combination.
    if (c.isVideoFile && !c.audioOnly) {
      _miniAudioOnly = true;
      await c.setAudioOnly(true);
    }
  }

  Future<void> _exitMini() async {
    if (!_mini) return;
    await windowManager.setOpacity(1);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setMaximumSize(const Size(100000, 100000));
    await windowManager.setMinimumSize(const Size(640, 420));
    final b = _fullBounds;
    if (b != null) await windowManager.setBounds(b);
    setState(() => _mini = false);
    c.setReducedLoad(false);
    if (_miniAudioOnly) {
      _miniAudioOnly = false;
      await c.setAudioOnly(false);
    }
  }

  Future<void> _saveBounds() async {
    if (_mini) {
      if (s.miniRememberPos)
        s.miniPosition = (await windowManager.getBounds()).topLeft;
      return;
    }
    if (!s.rememberWindow) return;
    if (_fullscreen || await windowManager.isMaximized()) return;
    if (await windowManager.isMinimized()) return;
    s.saveWindowBounds(await windowManager.getBounds());
  }

  @override
  void onWindowResized() => _saveBounds();

  @override
  void onWindowMoved() => _saveBounds();

  @override
  void onWindowMinimize() {
    c.setReducedLoad(true);
    if (widget.settings.autoAudioOnly && c.isVideoFile && !c.audioOnly) {
      _autoAudioOnly = true;
      c.setAudioOnly(true);
    }
  }

  @override
  void onWindowRestore() {
    c.setReducedLoad(_mini);
    if (_autoAudioOnly) {
      _autoAudioOnly = false;
      c.setAudioOnly(false);
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    final args = widget.initialArgs.where(isSupportedMedia).toList();
    if (args.isNotEmpty) {
      c.openPaths(args);
    } else {
      c.restore();
    }
  }

  Future<void> _toggleFullscreen([bool? value]) async {
    final next = value ?? !_fullscreen;
    await windowManager.setFullScreen(next);
    setState(() => _fullscreen = next);
  }

  Future<List<String>> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: [...audioExtensions, ...videoExtensions],
    );
    return [
      for (final f in r?.files ?? <PlatformFile>[])
        if (f.path != null) f.path!,
    ];
  }

  Future<void> _pickFile() async {
    final paths = await _pickFiles();
    if (paths.isEmpty) return;
    setState(() => _home = false);
    await c.openPaths(paths);
  }

  Future<void> _addFiles() async => c.addPaths(await _pickFiles());

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) await c.addPaths(mediaInFolder(dir));
  }

  Future<void> _openFolderFromHome() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final files = mediaInFolder(dir);
    if (files.isEmpty) return;
    setState(() => _home = false);
    await c.openPaths(files);
  }

  Future<void> _resume(HistoryEntry e) async {
    setState(() => _home = false);
    await c.openAt(e.path, Duration(milliseconds: e.posMs));
  }

  void _onShortcut(String name) {
    switch (name) {
      case 'play':
        c.togglePlay();
      case 'back':
        c.seekRelative(Duration(seconds: -c.seekStep));
      case 'fwd':
        c.seekRelative(Duration(seconds: c.seekStep));
      case 'volup':
        c.changeVolume(5);
      case 'voldown':
        c.changeVolume(-5);
      case 'mute':
        c.toggleMute();
      case 'audio':
        c.toggleAudioOnly();
      case 'fs':
        _toggleFullscreen();
      case 'exitfs':
        if (_fullscreen) _toggleFullscreen(false);
      case 'open':
        _pickFile();
      case 'mini':
        _mini ? _exitMini() : _enterMini();
      case 'next':
        c.next();
      case 'prev':
        c.previous();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): _NslIntent('play'),
        SingleActivator(LogicalKeyboardKey.keyK): _NslIntent('play'),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _NslIntent('back'),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NslIntent('fwd'),
        SingleActivator(LogicalKeyboardKey.arrowUp): _NslIntent('volup'),
        SingleActivator(LogicalKeyboardKey.arrowDown): _NslIntent('voldown'),
        SingleActivator(LogicalKeyboardKey.keyM): _NslIntent('mute'),
        SingleActivator(LogicalKeyboardKey.keyF): _NslIntent('fs'),
        SingleActivator(LogicalKeyboardKey.keyA): _NslIntent('audio'),
        SingleActivator(LogicalKeyboardKey.f11): _NslIntent('fs'),
        SingleActivator(LogicalKeyboardKey.escape): _NslIntent('exitfs'),
        SingleActivator(LogicalKeyboardKey.keyM, control: true): _NslIntent(
          'mini',
        ),
        SingleActivator(LogicalKeyboardKey.keyN): _NslIntent('next'),
        SingleActivator(LogicalKeyboardKey.keyP): _NslIntent('prev'),
        SingleActivator(LogicalKeyboardKey.keyO, control: true): _NslIntent(
          'open',
        ),
      },
      child: Actions(
        actions: {
          _NslIntent: CallbackAction<_NslIntent>(
            onInvoke: (i) {
              _onShortcut(i.name);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: DropTarget(
            onEnter: (_) => setState(() => _dragging = true),
            onLeave: () => setState(() => _dragging = false),
            onDrop: (d) {
              setState(() => _dragging = false);
              final paths = <String>[];
              for (final item in d.items.whereType<DropFileItem>()) {
                final p = item.localPath;
                if (p == null) continue;
                if (FileSystemEntity.isDirectorySync(p)) {
                  paths.addAll(mediaInFolder(p));
                } else if (isSupportedMedia(p)) {
                  paths.add(p);
                }
              }
              if (paths.isNotEmpty) setState(() => _home = false);
              c.openPaths(paths);
            },
            child: Scaffold(
              body: _mini
                  ? ListenableBuilder(
                      listenable: s,
                      builder: (context, _) => MiniPlayer(
                        controller: c,
                        opacity: s.miniOpacity,
                        onTop: s.miniOnTop,
                        onOpacity: (v) {
                          s.miniOpacity = v;
                          windowManager.setOpacity(v / 100);
                          setState(() {});
                        },
                        onToggleOnTop: () {
                          s.miniOnTop = !s.miniOnTop;
                          windowManager.setAlwaysOnTop(s.miniOnTop);
                          setState(() {});
                        },
                        onExpand: _exitMini,
                      ),
                    )
                  : Column(
                      children: [
                        if (!_fullscreen)
                          ListenableBuilder(
                            listenable: c,
                            builder: (_, _) => NslTitleBar(
                              title: c.title,
                              onHome: _home && !_settingsOpen
                                  ? null
                                  : () => setState(() {
                                      _home = true;
                                      _settingsOpen = false;
                                    }),
                            ),
                          ),
                        Expanded(
                          child: _settingsOpen
                              ? SettingsPage(
                                  settings: s,
                                  controller: c,
                                  history: widget.history,
                                  onClose: () =>
                                      setState(() => _settingsOpen = false),
                                )
                              : _home
                              ? HomePage(
                                  controller: c,
                                  history: widget.history,
                                  library: widget.library,
                                  onOpenFile: _pickFile,
                                  onOpenFolder: _openFolderFromHome,
                                  onMini: _enterMini,
                                  onSettings: _openSettings,
                                  onOpenPlayer: () =>
                                      setState(() => _home = false),
                                  onResume: _resume,
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: ListenableBuilder(
                                        listenable: c,
                                        builder: (context, _) {
                                          final openSettings = _openSettings;
                                          void toggleQueue() => setState(
                                            () => _showQueue = !_showQueue,
                                          );
                                          // Audio files and audio-only use the music layout.
                                          if (c.current != null &&
                                              !c.showVideo) {
                                            return MusicView(
                                              controller: c,
                                              onOpen: _pickFile,
                                              onSettings: openSettings,
                                              onToggleQueue: toggleQueue,
                                              onFullscreen: _toggleFullscreen,
                                              onMini: _enterMini,
                                            );
                                          }
                                          return Column(
                                            children: [
                                              Expanded(child: _buildStage()),
                                              if (!_fullscreen)
                                                ControlsBar(
                                                  controller: c,
                                                  onOpen: _pickFile,
                                                  onFullscreen:
                                                      _toggleFullscreen,
                                                  onSettings: openSettings,
                                                  onToggleQueue: toggleQueue,
                                                  onMini: _enterMini,
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                    if (!_fullscreen && _showQueue)
                                      QueuePanel(
                                        controller: c,
                                        onAddFiles: _addFiles,
                                        onAddFolder: _addFolder,
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: c.togglePlay,
          onDoubleTap: _toggleFullscreen,
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [NslStage.center, NslStage.edge],
                  stops: [0, 0.75],
                ),
              ),
              child: c.currentPath == null
                  ? const _EmptyState()
                  : c.showVideo
                  ? Video(controller: c.video, controls: NoVideoControls)
                  : _MusicView(title: c.title, audioOnlyVideo: c.isVideoFile),
            ),
          ),
        ),
        if (_dragging)
          Container(
            color: context.pal.accent.withValues(alpha: 0.12),
            alignment: Alignment.center,
            child: Text(
              'Drop to play',
              style: TextStyle(fontSize: 20, color: context.pal.accentInk),
            ),
          ),
      ],
    );
  }
}

class _NslIntent extends Intent {
  const _NslIntent(this.name);
  final String name;
}

class _MusicView extends StatelessWidget {
  const _MusicView({required this.title, required this.audioOnlyVideo});
  final String title;
  final bool audioOnlyVideo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2E313B)),
          ),
          child: const Icon(Icons.music_note, size: 64, color: NslStage.text),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, color: Color(0xFFECEDF1)),
          ),
        ),
        if (audioOnlyVideo)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Audio-only mode',
              style: TextStyle(fontSize: 12, color: NslStage.text),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.play_arrow_rounded, size: 56, color: NslStage.text),
        SizedBox(height: 14),
        Text(
          'DROP A FILE OR PRESS CTRL+O',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            color: NslStage.text,
          ),
        ),
      ],
    );
  }
}
