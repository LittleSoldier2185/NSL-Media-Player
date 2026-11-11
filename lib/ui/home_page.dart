import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/mini_ipc.dart';
import '../services/playlist_service.dart';
import 'controls.dart';
import 'library_view.dart';
import 'playlists_view.dart';
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
    required this.onSettings,
    required this.onOpenPlayer,
    required this.onResume,
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
  final VoidCallback onSettings;
  final VoidCallback onOpenPlayer;
  final void Function(HistoryEntry) onResume;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Section { home, library, playlists }

class _HomePageState extends State<HomePage> {
  _Section _section = _Section.home;
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
      children: [
        Expanded(
          child: Row(
            children: [
              _Nav(
                section: _section,
                onSelect: (s) => setState(() => _section = s),
                onSettings: widget.onSettings,
              ),
              Expanded(
                child: _section == _Section.library
                    ? LibraryView(
                        library: widget.library,
                        playlists: widget.playlists,
                        controller: widget.controller,
                        onOpenPlayer: widget.onOpenPlayer,
                      )
                    : _section == _Section.playlists
                    ? PlaylistsView(
                        playlists: widget.playlists,
                        library: widget.library,
                        controller: widget.controller,
                        onOpenPlayer: widget.onOpenPlayer,
                      )
                    : ListenableBuilder(
                        listenable: widget.history,
                        builder: (context, _) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(p),
                              const SizedBox(height: 28),
                              _continue(p),
                              const SizedBox(height: 28),
                              Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [_week(p), _library(p)],
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
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

  Widget _card(NslPalette p, {required Widget child, double width = 480}) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
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

  Widget _header(NslPalette p) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick up where you left off.',
              style: TextStyle(fontSize: 14, color: p.textDim),
            ),
          ],
        ),
        Wrap(
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
        ),
      ],
    );
  }

  Widget _continue(NslPalette p) {
    final items = widget.history.resumable
        .where((e) => File(e.path).existsSync())
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Continue',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Text(
            'Nothing to resume yet. Files you stop partway through show up here.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final e in items)
                SizedBox(
                  width: 260,
                  child: _ResumeCard(entry: e, onTap: () => widget.onResume(e)),
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
              height: 190,
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

  Widget _library(NslPalette p) {
    final c = widget.controller;
    final songs = c.queue.where((q) => !q.isVideo).length;
    final videos = c.queue.where((q) => q.isVideo).length;
    final top = widget.history.topThisMonth;
    Widget stat(String n, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            n,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: p.textDim)),
        ],
      ),
    );
    return _card(
      p,
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In your queue',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [stat('$songs', 'Songs'), stat('$videos', 'Videos')]),
          const SizedBox(height: 20),
          Text(
            'Most played this month',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.icon,
            ),
          ),
          const SizedBox(height: 4),
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
                constraints: const BoxConstraints(minHeight: 44),
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

class _Nav extends StatelessWidget {
  const _Nav({
    required this.section,
    required this.onSelect,
    required this.onSettings,
  });
  final _Section section;
  final ValueChanged<_Section> onSelect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget item(
      IconData icon,
      String label, {
      bool active = false,
      VoidCallback? onTap,
    }) {
      final enabled = active || onTap != null;
      return Tooltip(
        message: enabled ? '' : 'Coming soon',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active ? p.hover : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active
                      ? p.accentInk
                      : enabled
                      ? p.icon
                      : p.textDim.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: active
                        ? p.text
                        : enabled
                        ? p.icon
                        : p.textDim.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.titleBar,
        border: Border(right: BorderSide(color: p.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item(
            Icons.home_outlined,
            'Home',
            active: section == _Section.home,
            onTap: () => onSelect(_Section.home),
          ),
          item(
            Icons.folder_outlined,
            'Library',
            active: section == _Section.library,
            onTap: () => onSelect(_Section.library),
          ),
          item(
            Icons.list,
            'Playlists',
            active: section == _Section.playlists,
            onTap: () => onSelect(_Section.playlists),
          ),
          item(Icons.history, 'Recently played'),
          item(Icons.tune, 'Settings', onTap: onSettings),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.entry, required this.onTap});
  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    String fmt(int ms) {
      final d = Duration(milliseconds: ms);
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return d.inHours > 0
          ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
          : '${d.inMinutes}:$s';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
              Container(
                height: 100,
                color: p.track,
                alignment: Alignment.center,
                child: Icon(
                  entry.isVideo ? Icons.movie_outlined : Icons.music_note,
                  size: 20,
                  color: p.textDim,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                    Text(
                      entry.durMs > 0
                          ? '${fmt(entry.posMs)} of ${fmt(entry.durMs)}'
                          : fmt(entry.posMs),
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                    const SizedBox(height: 8),
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
