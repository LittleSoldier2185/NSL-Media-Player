import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/legacy.dart';

import '../player_controller/player_controller.dart';
import '../services/media_types.dart';
import '../services/mini_ipc.dart';
import '../services/mini_session_tracker.dart';
import '../services/settings_service.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import 'home_page.dart';
import 'mini_player.dart';
import 'music_view.dart';
import 'queue_panel.dart';
import 'settings_page.dart';
import 'shortcut_guard.dart';
import 'sidebar.dart';
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
  final List<String> initialArgs;

  /// Main window: starts the separate mini player process.
  final MiniHost? miniHost;

  /// Set when this process *is* the separate mini player.
  final MiniChild? miniChild;

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
  late bool _home =
      widget.miniChild == null && !widget.initialArgs.any(isSupportedMedia);

  /// The separate mini player process is open: it is the one playing.
  bool get _miniOpen => widget.miniHost?.active ?? false;

  /// Switches to the player page, unless the mini player is the one playing
  /// (the main window's own player is idle then).
  void _showPlayer() {
    if (_miniOpen) return;
    setState(() => _home = false);
  }

  // ---- sidebar / navigation ----

  /// Which hub page (Home, Library, Playlists) is shown while [_home] is true.
  NavDest _section = NavDest.home;

  /// What was showing before the sidebar was hidden, to bring back.
  SidebarMode _sidebarBeforeHide = SidebarMode.open;

  final _pageFocus = FocusNode(debugLabel: 'page');

  NavDest get _dest => _settingsOpen
      ? NavDest.settings
      : _home
      ? _section
      : NavDest.player;

  SidebarMode get _sidebar => SidebarMode.parse(s.sidebarMode);

  void _navigate(NavDest d) {
    setState(() {
      switch (d) {
        case NavDest.settings:
          _settingsOpen = true;
        case NavDest.player:
          _settingsOpen = false;
          if (!_miniOpen) _home = false;
        case NavDest.home || NavDest.library || NavDest.playlists:
          _settingsOpen = false;
          _home = true;
          _section = d;
      }
    });
  }

  /// Menu button / Ctrl+B: hide the sidebar, or bring back what was there.
  void _toggleSidebarHidden() {
    final now = _sidebar;
    if (now == SidebarMode.hidden) {
      s.sidebarMode = _sidebarBeforeHide.name;
    } else {
      _sidebarBeforeHide = now;
      s.sidebarMode = SidebarMode.hidden.name;
    }
  }

  /// Sidebar arrow: icons and names <-> icons only.
  void _toggleSidebarWide() {
    s.sidebarMode =
        (_sidebar == SidebarMode.open ? SidebarMode.rail : SidebarMode.open)
            .name;
  }

  /// After a click outside a text field, focus falls back to the page's
  /// scope, where the keyboard shortcuts do not reach. Give it back.
  void _restoreFocus() {
    if (!mounted) return;
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f == FocusScope.of(context)) _pageFocus.requestFocus();
  }

  /// True when audio-only was switched on by minimizing (not by the user).
  bool _autoAudioOnly = false;

  // Mini player state
  bool _mini = false;
  bool _miniAudioOnly = false; // audio-only switched on by entering mini
  Rect? _fullBounds;

  Timer? _resizeDebounce;

  // Mini window sizing: shaped like the video while a picture is shown, and
  // resizable by dragging its edges.
  Size? _miniApplied;
  Offset? _miniOriginOnce; // where to place the window on the next resize
  bool _miniResizing = false;
  bool _miniResizePending = false;

  NslPlayerController get c => widget.controller;
  AppSettings get s => widget.settings;

  /// Audio: the small card at the width the user chose. Video: picture-in-
  /// picture, shaped like the video, at the size the user chose.
  Size get _miniTarget => c.showVideo
      ? miniVideoSizeAt(c.videoAspect, s.miniScale)
      : Size(
          s.miniCardWidth.clamp(kMiniCardMinWidth, kMiniCardMaxWidth),
          kMiniCardHeight,
        );

  /// What the user may drag the mini window to: a video keeps its shape, the
  /// audio card only changes width.
  ({Size min, Size max, double aspect}) _miniLimits(Size target) {
    if (!c.showVideo) {
      return (
        min: const Size(kMiniCardMinWidth, kMiniCardHeight),
        max: const Size(kMiniCardMaxWidth, kMiniCardHeight),
        aspect: 0,
      );
    }
    final base = miniVideoSize(c.videoAspect);
    Size scaled(double k) => Size(
      (base.width * k).roundToDouble(),
      (base.height * k).roundToDouble(),
    );
    return (
      min: scaled(miniScaleMin(base)),
      max: scaled(miniScaleMax(base)),
      aspect: target.width / target.height,
    );
  }

  /// Remembers a size the user dragged the mini window to.
  void _rememberMiniSize(Size size) {
    if (c.showVideo) {
      s.miniScale = miniScaleForWidth(c.videoAspect, size.width);
    } else {
      s.miniCardWidth = size.width.clamp(kMiniCardMinWidth, kMiniCardMaxWidth);
    }
    // The window already has this size; do not resize it again.
    _miniApplied = _miniTarget;
  }

  /// Fits the mini window to what it shows (card only, or card + picture).
  /// Safe to call often: it does nothing when the size is already right, and
  /// overlapping calls are folded into one more pass.
  Future<void> _applyMiniSize() async {
    if (!_mini) return;
    if (_miniResizing) {
      _miniResizePending = true;
      return;
    }
    _miniResizing = true;
    try {
      do {
        _miniResizePending = false;
        final once = _miniOriginOnce;
        _miniOriginOnce = null;
        final target = _miniTarget;
        if (once == null) {
          if (target == _miniApplied) continue;
          // Leave a minimized window alone; it re-fits when restored.
          if (await windowManager.isMinimized()) continue;
        }
        _miniApplied = target;
        final origin = once ?? (await windowManager.getBounds()).topLeft;
        // Lift the previous limits and shape lock first so a bigger or
        // smaller target is never rejected, then set the new ones.
        await windowManager.setResizable(true);
        await windowManager.setAspectRatio(0);
        await windowManager.setMinimumSize(const Size(200, 100));
        await windowManager.setMaximumSize(const Size(100000, 100000));
        await windowManager.setBounds(
          Rect.fromLTWH(origin.dx, origin.dy, target.width, target.height),
        );
        final limits = _miniLimits(target);
        await windowManager.setMinimumSize(limits.min);
        await windowManager.setMaximumSize(limits.max);
        await windowManager.setAspectRatio(limits.aspect);
      } while (_miniResizePending && _mini);
    } finally {
      _miniResizing = false;
    }
  }

  void _onControllerChanged() {
    if (_mini) _applyMiniSize();
  }

  // ---- separate mini player process: main window side ----

  bool _wasMiniOpen = false;

  /// The mini player process opened, or handed playback back.
  void _onMiniHost() {
    final open = _miniOpen;
    final host = widget.miniHost!;
    if (_wasMiniOpen &&
        !open &&
        host.lastReturn == MiniReturn.expand &&
        mounted) {
      _home = false; // it continues here: show the player
    }
    _wasMiniOpen = open;
    if (mounted) setState(() {});
  }

  /// Opens the mini player. By default it is a separate window and the main
  /// window stays open; if that cannot be started (or the setting is off) the
  /// main window itself shrinks into the mini player instead.
  Future<void> _openMini() async {
    final host = widget.miniHost;
    if (host == null || !s.miniSeparateWindow) return _enterMini();
    if (host.active) return; // already open
    if (_fullscreen) await _toggleFullscreen(false);
    final bounds = await windowManager.getBounds();
    final started = await host.launch(origin: bounds.topLeft);
    if (!started) {
      await _enterMini();
      return;
    }
    // The main window's own player is idle now; show something useful.
    if (mounted) setState(() => _home = true);
  }

  // ---- separate mini player process: mini side ----

  final _tracker = MiniSessionTracker();
  final List<StreamSubscription<Object?>> _miniSubs = [];
  bool _miniFinishing = false;

  /// Starts this process as the mini player: load what the main window was
  /// playing, then open the small window and carry on.
  Future<void> _bootMiniProcess() async {
    final child = widget.miniChild!;
    final init = child.init;
    // Closing the window must report back to the main window first.
    await windowManager.setPreventClose(true);
    final paths = [
      for (final p in (init['queue'] as List? ?? const <Object?>[])) '$p',
    ];
    final index = init['index'] is int ? init['index'] as int : 0;
    final posMs = init['posMs'] is int ? init['posMs'] as int : 0;
    final playing = init['playing'] == true;
    try {
      if (init['volume'] is num) {
        await c.setVolume((init['volume'] as num).toDouble());
      }
      if (init['speed'] is num) {
        await c.setSpeed((init['speed'] as num).toDouble());
      }
    } on Object catch (e) {
      debugPrint('Could not copy volume/speed: $e');
    }
    await c.adoptState(
      paths: paths,
      index: index,
      position: Duration(milliseconds: posMs),
      play: false,
    );
    _attachTracker();
    _miniSubs.add(child.commands.listen(_onMiniCommand));
    await _enterMini();
    await windowManager.show();
    if (playing) await c.player.play();
  }

  /// Watches what is played so the main window can add it to the history.
  void _attachTracker() {
    var lastPath = c.currentPath;
    _tracker.trackChanged(lastPath, countPlay: false); // main counted this one
    c.addListener(() {
      final p = c.currentPath;
      if (p != lastPath) {
        lastPath = p;
        _tracker.trackChanged(p);
      }
    });
    _miniSubs.add(c.player.stream.playing.listen(_tracker.playingChanged));
    _miniSubs.add(
      c.player.stream.position.listen(
        (pos) => _tracker.progress(
          pos.inMilliseconds,
          c.player.state.duration.inMilliseconds,
        ),
      ),
    );
  }

  /// "Play this" and friends, forwarded by the main window.
  void _onMiniCommand(Json m) {
    List<String> paths() => [
      for (final p in (m['paths'] as List? ?? const <Object?>[])) '$p',
    ];
    switch (m['cmd']) {
      case 'open':
        final list = paths();
        final at = m['posMs'];
        if (at is int && list.length == 1) {
          c.openAt(list.first, Duration(milliseconds: at));
        } else {
          c.openPaths(list, start: m['start'] is int ? m['start'] as int : 0);
        }
      case 'add':
        c.addPaths(paths());
      case 'toggle':
        c.togglePlay();
      case 'next':
        c.next();
      case 'prev':
        c.previous();
      case 'return':
        _finishMini('expand');
    }
  }

  /// Hands playback back to the main window and quits this process.
  /// [evt] is 'expand' (carry on there) or 'close' (leave it paused).
  Future<void> _finishMini(String evt) async {
    if (_miniFinishing) return;
    _miniFinishing = true;
    final child = widget.miniChild!;
    final prefs = {
      for (final k in miniPrefKeys)
        if (s.prefs.get(k) != null) k: s.prefs.get(k),
    };
    final delivered = await child.finish(
      evt,
      state: c.snapshot(),
      prefs: prefs,
      history: _tracker.results(),
    );
    if (!delivered && evt == 'expand') {
      // The main window was closed meanwhile: open the app again with this file.
      final path = c.currentPath;
      try {
        await Process.start(Platform.resolvedExecutable, [
          ?path,
        ], mode: ProcessStartMode.detached);
      } on Object catch (e) {
        debugPrint('Could not reopen the main window: $e');
      }
    }
    exit(0);
  }

  /// The mini player's own close button / Alt+F4.
  void _closeMini() {
    if (widget.miniChild != null) {
      _finishMini('close');
    } else {
      windowManager.close();
    }
  }

  @override
  void onWindowClose() {
    if (widget.miniChild != null) _finishMini('close');
  }

  Future<void> _enterMini() async {
    if (_mini) return;
    if (_fullscreen) await _toggleFullscreen(false);
    _fullBounds = await windowManager.getBounds();
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    // Set first so the resize events below are not saved as the full-window size.
    setState(() => _mini = true);
    _miniApplied = null;
    // Sound-only mode is chosen before sizing so the window opens the right size.
    if (c.isVideoFile && !c.audioOnly && !s.miniShowVideo) {
      _miniAudioOnly = true;
      await c.setAudioOnly(true);
    }
    final pos = s.miniRememberPos ? s.miniPosition : null;
    _miniOriginOnce = pos ?? widget.miniChild?.origin ?? _fullBounds!.topLeft;
    await _applyMiniSize();
    await windowManager.setAlwaysOnTop(s.miniOnTop);
    await windowManager.setOpacity(s.miniOpacity / 100);
    c.setReducedLoad(true);
  }

  /// Mini player button: picture + sound <-> sound only.
  void _toggleMiniVideo() {
    // The user's own choice now; do not undo it when leaving mini.
    _miniAudioOnly = false;
    c.toggleAudioOnly();
  }

  Future<void> _exitMini() async {
    if (!_mini) return;
    // In the separate mini player, "expand" means: back to the main window.
    if (widget.miniChild != null) return _finishMini('expand');
    // Stop any in-flight mini resize from fighting the restore below.
    _miniResizePending = false;
    _miniApplied = null;
    await windowManager.setOpacity(1);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setAspectRatio(0);
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
      if (await windowManager.isMinimized()) return;
      final b = await windowManager.getBounds();
      if (s.miniRememberPos) s.miniPosition = b.topLeft;
      // Our own resizing is not the user's choice; only remember drags.
      if (!_miniResizing) _rememberMiniSize(b.size);
      return;
    }
    if (!s.rememberWindow) return;
    if (_fullscreen || await windowManager.isMaximized()) return;
    if (await windowManager.isMinimized()) return;
    s.saveWindowBounds(await windowManager.getBounds());
  }

  @override
  void onWindowResized() => _saveBounds();

  /// While the user drags a mini window edge: save once they pause, in case
  /// the "resized" event does not arrive.
  @override
  void onWindowResize() {
    if (!_mini || _miniResizing) return;
    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 350), _saveBounds);
  }

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
    FocusManager.instance.removeListener(_restoreFocus);
    _pageFocus.dispose();
    _resizeDebounce?.cancel();
    for (final sub in _miniSubs) {
      sub.cancel();
    }
    widget.miniHost?.removeListener(_onMiniHost);
    windowManager.removeListener(this);
    c.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    c.addListener(_onControllerChanged);
    widget.miniHost?.addListener(_onMiniHost);
    FocusManager.instance.addListener(_restoreFocus);
    if (widget.miniChild != null) {
      // The separate mini player: play what the main window handed over.
      unawaited(_bootMiniProcess());
      return;
    }
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
    _showPlayer();
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
    _showPlayer();
    await c.openPaths(files);
  }

  Future<void> _resume(HistoryEntry e) async {
    _showPlayer();
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
        _mini ? _exitMini() : _openMini();
      case 'home':
        _navigate(NavDest.home);
      case 'sidebar':
        _toggleSidebarHidden();
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
        SingleActivator(LogicalKeyboardKey.keyH): _NslIntent('home'),
        SingleActivator(LogicalKeyboardKey.keyB, control: true): _NslIntent(
          'sidebar',
        ),
      },
      child: Actions(
        actions: {
          // Plain keys step aside while the user types in a text field.
          _NslIntent: GuardedAction<_NslIntent>(
            onInvoke: (i) => _onShortcut(i.name),
            isPlainKey: (i) => i.plain,
          ),
        },
        child: Focus(
          focusNode: _pageFocus,
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
              if (paths.isNotEmpty) _showPlayer();
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
                        onToggleVideo: _toggleMiniVideo,
                        onClose: _closeMini,
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
                              onMenu: _toggleSidebarHidden,
                              onLogo: () => _navigate(NavDest.home),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              // Sidebar: hidden in fullscreen; icons only
                              // in a narrow window so the content keeps room.
                              if (!_fullscreen)
                                Builder(
                                  builder: (context) {
                                    final narrow =
                                        MediaQuery.sizeOf(context).width < 760;
                                    final mode =
                                        narrow && _sidebar == SidebarMode.open
                                        ? SidebarMode.rail
                                        : _sidebar;
                                    return AppSidebar(
                                      mode: mode,
                                      current: _dest,
                                      onSelect: _navigate,
                                      onToggleWide: _toggleSidebarWide,
                                    );
                                  },
                                ),
                              Expanded(
                                child: _settingsOpen
                                    ? SettingsPage(
                                        settings: s,
                                        controller: c,
                                        history: widget.history,
                                        library: widget.library,
                                        onClose: () => setState(
                                          () => _settingsOpen = false,
                                        ),
                                      )
                                    : _home
                                    ? HomePage(
                                        controller: c,
                                        history: widget.history,
                                        library: widget.library,
                                        playlists: widget.playlists,
                                        onOpenFile: _pickFile,
                                        onOpenFolder: _openFolderFromHome,
                                        onMini: _openMini,
                                        section: _section,
                                        onOpenPlayer: _showPlayer,
                                        miniHost: widget.miniHost,
                                        onResume: _resume,
                                        onOpenLibrary: () =>
                                            _navigate(NavDest.library),
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: _HomeOverlay(
                                              controller: c,
                                              // The sidebar (which has Home) is hidden, or this is fullscreen.
                                              enabled:
                                                  _fullscreen ||
                                                  _sidebar ==
                                                      SidebarMode.hidden,
                                              fullscreen: _fullscreen,
                                              onHome: () =>
                                                  _navigate(NavDest.home),
                                              onExitFullscreen: () =>
                                                  _toggleFullscreen(false),
                                              child: ListenableBuilder(
                                                listenable: c,
                                                builder: (context, _) {
                                                  final openSettings =
                                                      _openSettings;
                                                  void toggleQueue() =>
                                                      setState(
                                                        () => _showQueue =
                                                            !_showQueue,
                                                      );
                                                  // Audio files and audio-only use the music layout.
                                                  if (c.current != null &&
                                                      !c.showVideo) {
                                                    return MusicView(
                                                      controller: c,
                                                      onOpen: _pickFile,
                                                      onSettings: openSettings,
                                                      onToggleQueue:
                                                          toggleQueue,
                                                      onFullscreen:
                                                          _toggleFullscreen,
                                                      onMini: _openMini,
                                                    );
                                                  }
                                                  return Column(
                                                    children: [
                                                      Expanded(
                                                        child: _buildStage(),
                                                      ),
                                                      if (!_fullscreen)
                                                        ControlsBar(
                                                          controller: c,
                                                          onOpen: _pickFile,
                                                          onFullscreen:
                                                              _toggleFullscreen,
                                                          onSettings:
                                                              openSettings,
                                                          onToggleQueue:
                                                              toggleQueue,
                                                          onMini: _openMini,
                                                        ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          if (!_fullscreen && _showQueue)
                                            QueuePanel(
                                              controller: c,
                                              playlists: widget.playlists,
                                              thumbnails:
                                                  widget.library.thumbnails,
                                              onAddFiles: _addFiles,
                                              onAddFolder: _addFolder,
                                            ),
                                        ],
                                      ),
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

  /// A single key with no Ctrl: must not fire while the user is typing.
  bool get plain => !const {'mini', 'open', 'sidebar'}.contains(name);
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

/// Wraps the player area. While the sidebar is hidden (or in fullscreen) a
/// "Home" button floats over the top-left of the picture. It shows when the
/// mouse moves or while paused, and fades out, with the cursor, a few seconds
/// after the mouse stops while playing.
class _HomeOverlay extends StatefulWidget {
  const _HomeOverlay({
    required this.controller,
    required this.enabled,
    required this.fullscreen,
    required this.onHome,
    required this.onExitFullscreen,
    required this.child,
  });

  final NslPlayerController controller;
  final bool enabled;
  final bool fullscreen;
  final VoidCallback onHome;
  final VoidCallback onExitFullscreen;
  final Widget child;

  @override
  State<_HomeOverlay> createState() => _HomeOverlayState();
}

class _HomeOverlayState extends State<_HomeOverlay> {
  static const idle = Duration(seconds: 3);
  bool _active = true;
  Timer? _timer;

  void _poke() {
    if (!_active) setState(() => _active = true);
    _timer?.cancel();
    _timer = Timer(idle, () {
      if (mounted) setState(() => _active = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _poke();
  }

  @override
  void didUpdateWidget(_HomeOverlay old) {
    super.didUpdateWidget(old);
    // Just became available (sidebar hidden / fullscreen): show it at once.
    if (widget.enabled && !old.enabled) _poke();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pl = widget.controller.player;
    return StreamBuilder<bool>(
      stream: pl.stream.playing,
      initialData: pl.state.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
        // Paused: always visible, nothing to hide the cursor for.
        final visible = widget.enabled && (_active || !playing);
        return MouseRegion(
          onHover: (_) => _poke(),
          onEnter: (_) => _poke(),
          cursor: widget.enabled && !visible
              ? SystemMouseCursors.none
              : MouseCursor.defer,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (widget.enabled)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: _scrim(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _scrim() {
    const white = Color(0xFFECEDF1);
    return Container(
      height: 84,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB8000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Back to Home (H)',
            child: Material(
              color: const Color(0xCC101116),
              shape: const StadiumBorder(
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: widget.onHome,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.only(left: 10, right: 12),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left, size: 20, color: white),
                      SizedBox(width: 2),
                      Text(
                        'Home',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: white,
                        ),
                      ),
                      SizedBox(width: 8),
                      _Kbd('H'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          if (widget.fullscreen)
            Tooltip(
              message: 'Exit fullscreen (Esc)',
              child: Material(
                color: const Color(0xCC101116),
                shape: const CircleBorder(
                  side: BorderSide(color: Color(0x33FFFFFF)),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onExitFullscreen,
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.fullscreen_exit, size: 20, color: white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small key label, like a keyboard key.
class _Kbd extends StatelessWidget {
  const _Kbd(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x24FFFFFF),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFFECEDF1),
      ),
    ),
  );
}
