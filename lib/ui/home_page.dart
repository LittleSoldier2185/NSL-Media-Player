import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/mini_ipc.dart';
import '../services/playlist_service.dart';
import '../services/thumbnail_service.dart';
import 'controls.dart';
import 'library_thumb.dart';
import 'library_view.dart';
import 'playlists_view.dart';
import 'sidebar.dart';
import 'theme.dart';

/// Home + Dashboard, following the "Home + Dashboard" board of the UI design.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.history,
    required this.library,
    required this.playlists,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onMini,
    required this.section,
    required this.onOpenPlayer,
    required this.onResume,
    required this.onOpenLibrary,
    this.miniHost,
  });

  /// When a separate mini player is open, Home says so (the main window's
  /// own player is idle) and offers to bring playback back here.
  final MiniHost? miniHost;

  final NslPlayerController controller;
  final HistoryService history;
  final LibraryService library;
  final PlaylistService playlists;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onMini;

  /// Which part of the hub to show: home, library or playlists (chosen in
  /// the sidebar).
  final NavDest section;
  final VoidCallback onOpenPlayer;
  final void Function(HistoryEntry) onResume;

  /// "See all in Library" and the empty "Add a folder" prompt.
  final VoidCallback onOpenLibrary;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _table = false;
  int? _hover;

  static const _dayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLong = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      // Stretch: every page below (Home, Library, Playlists) must fill the
      // full width. Without it the scroll views shrink to their content and
      // sit in the middle of the window.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: switch (widget.section) {
            NavDest.library => LibraryView(
              library: widget.library,
              playlists: widget.playlists,
              controller: widget.controller,
              onOpenPlayer: widget.onOpenPlayer,
            ),
            NavDest.playlists => PlaylistsView(
              playlists: widget.playlists,
              library: widget.library,
              controller: widget.controller,
              onOpenPlayer: widget.onOpenPlayer,
            ),
            _ => ListenableBuilder(
              listenable: Listenable.merge([widget.history, widget.library]),
              builder: (context, _) => _homeScroll(p),
            ),
          },
        ),
        // While a separate mini player is open it is the one playing; this
        // window's own player is idle, so say so instead of showing it.
        if (widget.miniHost != null)
          ListenableBuilder(
            listenable: widget.miniHost!,
            builder: (_, _) => widget.miniHost!.active
                ? _MiniBanner(onBringBack: widget.miniHost!.bringBack)
                : _NowPlayingBar(
                    controller: widget.controller,
                    onOpenPlayer: widget.onOpenPlayer,
                  ),
          )
        else
          _NowPlayingBar(
            controller: widget.controller,
            onOpenPlayer: widget.onOpenPlayer,
          ),
      ],
    );
  }

  Widget _card(NslPalette p, {required Widget child, double? width}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.panelBorder),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.panelTop, p.panelBottom],
        ),
      ),
      child: child,
    );
  }

  /// The Home page: a centered column at most [_maxWidth] wide that reflows
  /// as the window (or the sidebar) changes the room available.
  static const _maxWidth = 1180.0;

  Widget _homeScroll(NslPalette p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(p, w),
                  const SizedBox(height: 30),
                  _continue(p, w),
                  const SizedBox(height: 34),
                  _stats(p, w),
                  const SizedBox(height: 34),
                  _recent(p, w),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(NslPalette p, String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _header(NslPalette p, double w) {
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _greeting(),
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            color: p.text,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick up where you left off.',
          style: TextStyle(fontSize: 14, color: p.textDim),
        ),
      ],
    );
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: widget.onOpenFile,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Open file'),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            minimumSize: const Size(0, 44),
          ),
        ),
        OutlinedButton(
          onPressed: widget.onOpenFolder,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Open folder'),
        ),
        OutlinedButton(
          onPressed: widget.onMini,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Mini player'),
        ),
      ],
    );
    // Wide: greeting on the left, actions on the right edge. Narrow: stacked.
    if (w >= 760) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: greeting),
          buttons,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [greeting, const SizedBox(height: 16), buttons],
    );
  }

  /// Files that were stopped partway, newest first (at most three).
  List<HistoryEntry> get _resumable =>
      widget.history.resumable.where((e) => File(e.path).existsSync()).toList();

  Widget _continue(NslPalette p, double w) {
    final items = _resumable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(p, 'Continue'),
        if (items.isEmpty)
          Text(
            'Nothing to resume yet. Files you stop partway through show up here.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
          _continueBody(items, w),
      ],
    );
  }

  Widget _continueBody(List<HistoryEntry> items, double w) {
    final thumbs = widget.library.thumbnails;
    final hero = _HeroCard(
      entry: items.first,
      thumbnails: thumbs,
      onTap: () => widget.onResume(items.first),
    );
    final rest = [
      for (final e in items.skip(1))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _MiniResume(
            entry: e,
            thumbnails: thumbs,
            onTap: () => widget.onResume(e),
          ),
        ),
    ];
    if (rest.isEmpty) {
      // One item: the big card alone, not stretched across the whole width.
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: hero,
      );
    }
    if (w >= 820) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 155, child: hero),
          const SizedBox(width: 20),
          Expanded(flex: 100, child: Column(children: rest)),
        ],
      );
    }
    return Column(children: [hero, const SizedBox(height: 14), ...rest]);
  }

  Widget _stats(NslPalette p, double w) {
    if (w >= 760) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: _week(p)),
            const SizedBox(width: 20),
            Expanded(child: _mostPlayed(p)),
          ],
        ),
      );
    }
    return Column(
      children: [_week(p), const SizedBox(height: 16), _mostPlayed(p)],
    );
  }

  /// The newest files of the Library, as many as fit in one row.
  Widget _recent(NslPalette p, double w) {
    final lib = widget.library;
    final trailing = TextButton(
      onPressed: widget.onOpenLibrary,
      child: Text(
        lib.items.isEmpty ? 'Open Library' : 'See all in Library',
        style: TextStyle(color: p.accentInk, fontSize: 13),
      ),
    );
    if (lib.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(p, 'Recently added', trailing: trailing),
          _card(
            p,
            child: Row(
              children: [
                Icon(Icons.create_new_folder_outlined, color: p.icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Add the folders where you keep your music and videos and '
                    'the newest files will show up here.',
                    style: TextStyle(fontSize: 13.5, color: p.textDim),
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton(
                  onPressed: widget.onOpenLibrary,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Add a folder'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    const gap = 16.0;
    final cols = ((w + gap) / (176 + gap)).floor().clamp(2, 6);
    final tileW = (w - gap * (cols - 1)) / cols;
    final shown = lib.query(sort: LibrarySort.recent).take(cols).toList();
    final paths = [for (final i in shown) i.path];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(p, 'Recently added', trailing: trailing),
        Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < shown.length; i++)
              SizedBox(
                width: tileW,
                child: _RecentTile(
                  item: shown[i],
                  library: lib,
                  onTap: () async {
                    await widget.controller.openPaths(paths, start: i);
                    widget.onOpenPlayer();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _hm(double seconds) {
    final m = (seconds / 60).round();
    return '${m ~/ 60}h ${m % 60}m';
  }

  Widget _week(NslPalette p) {
    final week = widget.history.lastWeek;
    final total = week.fold<double>(0, (a, b) => a + b.$2);
    final maxH = week
        .map((w) => w.$2 / 3600)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final axisMax = maxH <= 1 ? 1.0 : maxH.ceilToDouble();
    return _card(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last 7 days',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    Text(
                      'Watch and listen time, hours per day',
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ],
                ),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Chart')),
                  ButtonSegment(value: true, label: Text('Table')),
                ],
                selected: {_table},
                onSelectionChanged: (v) => setState(() => _table = v.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _hm(total),
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w600,
              color: p.text,
              height: 1,
            ),
          ),
          const SizedBox(height: 16),
          if (_table)
            for (final w in week)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.panelBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _dayLong[w.$1.weekday - 1],
                      style: TextStyle(fontSize: 13, color: p.icon),
                    ),
                    Text(
                      '${(w.$2 / 3600).toStringAsFixed(1)} h',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < week.length; i++)
                    Expanded(
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _hover = i),
                        onExit: (_) => setState(() => _hover = null),
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  FractionallySizedBox(
                                    heightFactor:
                                        ((week[i].$2 / 3600) / axisMax).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                    child: Container(
                                      width: 24,
                                      decoration: BoxDecoration(
                                        color: p.accent.withValues(
                                          alpha: _hover == null || _hover == i
                                              ? 1
                                              : 0.45,
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(4),
                                            ),
                                      ),
                                    ),
                                  ),
                                  if (_hover == i)
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Text(
                                        '${(week[i].$2 / 3600).toStringAsFixed(1)} h',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: p.text,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _dayShort[week[i].$1.weekday - 1],
                              style: TextStyle(fontSize: 12, color: p.textDim),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _mostPlayed(NslPalette p) {
    final top = widget.history.topThisMonth;
    return _card(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Most played this month',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 8),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nothing played yet.',
                style: TextStyle(fontSize: 13, color: p.textDim),
              ),
            )
          else
            for (var i = 0; i < top.length; i++)
              Container(
                constraints: const BoxConstraints(minHeight: 46),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.panelBorder)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 13, color: p.textDim),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        fileNameOf(top[i].$1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${top[i].$2} plays',
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// 1:23 style clock from milliseconds.
String _clock(int ms) {
  final d = Duration(milliseconds: ms);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
      : '${d.inMinutes}:$s';
}

/// "just now", "3 h ago", "yesterday", "5 days ago".
String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inHours < 48) return 'yesterday';
  return '${d.inDays} days ago';
}

String _progressText(HistoryEntry e) =>
    e.durMs > 0 ? '${_clock(e.posMs)} of ${_clock(e.durMs)}' : _clock(e.posMs);

/// The biggest "Continue" card: a large picture with a play button, the
/// title and how far you got.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.entry,
    required this.thumbnails,
    required this.onTap,
  });
  final HistoryEntry entry;
  final ThumbnailService thumbnails;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.panelBorder),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.panelTop, p.panelBottom],
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 250,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PathThumb(
                      path: entry.path,
                      thumbnails: thumbnails,
                      fit: entry.isVideo ? BoxFit.cover : BoxFit.contain,
                      iconSize: 40,
                    ),
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xB80B0C10),
                          border: Border.all(color: const Color(0x4DFFFFFF)),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.isVideo ? 'Video' : 'Audio'} · '
                      '${_progressText(entry)} · ${_ago(entry.lastPlayed)}',
                      style: TextStyle(fontSize: 12.5, color: p.textDim),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: entry.fraction,
                        minHeight: 4,
                        color: p.accent,
                        backgroundColor: p.track,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A smaller "Continue" entry: picture on the left, title and progress.
class _MiniResume extends StatelessWidget {
  const _MiniResume({
    required this.entry,
    required this.thumbnails,
    required this.onTap,
  });
  final HistoryEntry entry;
  final ThumbnailService thumbnails;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.panelBorder),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.panelTop, p.panelBottom],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 150,
                height: 84,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PathThumb(
                  path: entry.path,
                  thumbnails: thumbnails,
                  fit: entry.isVideo ? BoxFit.cover : BoxFit.contain,
                  iconSize: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _progressText(entry),
                      style: TextStyle(fontSize: 12.5, color: p.textDim),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: entry.fraction,
                        minHeight: 4,
                        color: p.accent,
                        backgroundColor: p.track,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tile of the "Recently added" row.
class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.item,
    required this.library,
    required this.onTap,
  });
  final LibraryItem item;
  final LibraryService library;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LibraryThumb(
                item: item,
                library: library,
                fit: item.isVideo ? BoxFit.cover : BoxFit.contain,
                iconSize: 28,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown at the bottom of Home while the separate mini player is playing.
class _MiniBanner extends StatelessWidget {
  const _MiniBanner({required this.onBringBack});
  final VoidCallback onBringBack;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: p.panelTop,
        border: Border(top: BorderSide(color: p.panelBorder)),
      ),
      child: Row(
        children: [
          Icon(Icons.picture_in_picture_alt, size: 18, color: p.accentInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Playing in the mini player. Pick something here to play it there.',
              style: TextStyle(fontSize: 13, color: p.text),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onBringBack,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Bring back here'),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({required this.controller, required this.onOpenPlayer});
  final NslPlayerController controller;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pl = controller.player;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.current == null) return const SizedBox.shrink();
        final title = Text(
          controller.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
        );
        final transport = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBtn(
              Icons.skip_previous,
              controller.previous,
              tooltip: 'Previous',
            ),
            StreamBuilder<bool>(
              stream: pl.stream.playing,
              initialData: pl.state.playing,
              builder: (_, s) => PlayButton(
                playing: s.data ?? false,
                onTap: controller.togglePlay,
                size: 40,
              ),
            ),
            IconBtn(Icons.skip_next, controller.next, tooltip: 'Next'),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: onOpenPlayer,
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Open player'),
            ),
          ],
        );
        final seek = SeekRow(controller: controller);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: p.panelTop,
            border: Border(top: BorderSide(color: p.panelBorder)),
          ),
          // Wide: title | time bar | buttons on one line. Narrow: the time
          // bar gets a line of its own so nothing is squeezed.
          child: LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 880
                ? Row(
                    children: [
                      Expanded(flex: 3, child: title),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: seek),
                      const SizedBox(width: 12),
                      transport,
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: title),
                          transport,
                        ],
                      ),
                      seek,
                    ],
                  ),
          ),
        );
      },
    );
  }
}
