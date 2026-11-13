import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import 'home_sections.dart';
import 'playlist_dialogs.dart';
import 'file_menu.dart';
import 'theme.dart';
import 'time_format.dart';

/// Which files the History page lists.
enum HistoryKind { all, videos, music }

/// The History page: everything that was played, newest first, grouped by
/// day. Can be filtered, searched, cleaned up one file at a time or cleared.
class HistoryView extends StatefulWidget {
  const HistoryView({
    super.key,
    required this.history,
    required this.library,
    required this.playlists,
    required this.controller,
    required this.onOpenPlayer,
    required this.onResume,
  });

  final HistoryService history;
  final LibraryService library;
  final PlaylistService playlists;
  final NslPlayerController controller;
  final VoidCallback onOpenPlayer;
  final void Function(HistoryEntry) onResume;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

/// One line of the flattened list: a day heading or a played file.
class HistoryLine {
  const HistoryLine.header(this.day) : entry = null, position = 0;
  const HistoryLine.row(this.entry, this.position) : day = null;

  final HistoryDay? day;
  final HistoryEntry? entry;

  /// 0 only, 1 first, 2 middle, 3 last (for the rounded group card).
  final int position;
}

/// The entries that pass the filter and the search, as a flat list of day
/// headings and rows (so a ListView.builder can build it lazily). Rows carry
/// their place in the day's rounded card: only / first / middle / last.
List<HistoryLine> buildHistoryLines({
  required List<HistoryEntry> entries,
  required Map<String, LibraryItem> byPath,
  required HistoryKind kind,
  String query = '',
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  final matching = <HistoryEntry>[
    for (final e in entries)
      if (switch (kind) {
            HistoryKind.all => true,
            HistoryKind.videos => e.isVideo,
            HistoryKind.music => !e.isVideo,
          } &&
          (q.isEmpty ||
              (byPath[e.path.toLowerCase()]?.title ?? e.title)
                  .toLowerCase()
                  .contains(q) ||
              (byPath[e.path.toLowerCase()]?.artist ?? '')
                  .toLowerCase()
                  .contains(q)))
        e,
  ];
  final at = now ?? DateTime.now();
  final out = <HistoryLine>[];
  HistoryDay? current;
  for (var i = 0; i < matching.length; i++) {
    final e = matching[i];
    final day = historyDay(e.lastPlayed, now: at);
    final firstOfDay = day != current;
    if (firstOfDay) {
      current = day;
      out.add(HistoryLine.header(day));
    }
    final nextDay = i + 1 < matching.length
        ? historyDay(matching[i + 1].lastPlayed, now: at)
        : null;
    final lastOfDay = nextDay != day;
    out.add(
      HistoryLine.row(
        e,
        firstOfDay && lastOfDay
            ? 0
            : firstOfDay
            ? 1
            : lastOfDay
            ? 3
            : 2,
      ),
    );
  }
  return out;
}

class _HistoryViewState extends State<HistoryView> {
  final _search = TextEditingController();
  HistoryKind _kind = HistoryKind.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /// Resume where it stopped, or start over if it had ended.
  void _play(HistoryEntry e) {
    if (!File(e.path).existsSync()) {
      _toast('That file is not there any more.');
      return;
    }
    if (e.resumable) {
      widget.onResume(e);
    } else {
      widget.controller.openPaths([e.path]);
      widget.onOpenPlayer();
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes the list of what you played, the Continue shelf and '
          'the play counts. Your files are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) widget.history.clear();
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Clock time for today and yesterday, weekday for this week, else a date.
  String _when(HistoryEntry e) {
    final t = e.lastPlayed;
    return switch (historyDay(t)) {
      HistoryDay.today || HistoryDay.yesterday => timeOfDayText(t),
      HistoryDay.thisWeek => _weekdays[t.weekday - 1],
      HistoryDay.earlier => '${_months[t.month - 1]} ${t.day}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.history, widget.library, _search]),
      builder: (context, _) {
        final byPath = {
          for (final i in widget.library.items) i.path.toLowerCase(): i,
        };
        final lines = buildHistoryLines(
          entries: widget.history.entries,
          byPath: byPath,
          kind: _kind,
          query: _search.text,
        );
        final total = widget.history.entries.length;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 32, 40, 0),
                  child: _header(p, total),
                ),
                Expanded(
                  child: lines.isEmpty
                      ? _empty(p, total)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                          itemCount: lines.length,
                          itemBuilder: (context, i) =>
                              _buildLine(p, lines[i], byPath),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(NslPalette p, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Everything you played, newest first. Kept on this computer only.',
                    style: TextStyle(fontSize: 14, color: p.textDim),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: total == 0 ? null : _clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear history'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ],
        ),
        if (!widget.history.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: p.accentInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'History is turned off in Settings > Library, so new plays '
                    'are not recorded.',
                    style: TextStyle(fontSize: 13, color: p.textDim),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<HistoryKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: HistoryKind.all, label: Text('All')),
                ButtonSegment(value: HistoryKind.videos, label: Text('Videos')),
                ButtonSegment(value: HistoryKind.music, label: Text('Music')),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search your history',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: _search.clear,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _empty(NslPalette p, int total) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        total == 0
            ? 'Nothing played yet. Files you play show up here.'
            : 'No matches.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.5, color: p.textDim),
      ),
    ),
  );

  Widget _buildLine(
    NslPalette p,
    HistoryLine line,
    Map<String, LibraryItem> byPath,
  ) {
    final day = line.day;
    if (day != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
        child: Text(
          day.label.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: p.textDim,
          ),
        ),
      );
    }
    final e = line.entry!;
    final pos = line.position;
    final radius = BorderRadius.vertical(
      top: Radius.circular(pos == 0 || pos == 1 ? 16 : 0),
      bottom: Radius.circular(pos == 0 || pos == 3 ? 16 : 0),
    );
    final missing = !File(e.path).existsSync();
    return Container(
      margin: EdgeInsets.only(bottom: pos == 0 || pos == 3 ? 26 : 0),
      decoration: BoxDecoration(
        color: p.panelTop,
        borderRadius: radius,
        border: Border(
          left: BorderSide(color: p.panelBorder),
          right: BorderSide(color: p.panelBorder),
          top: BorderSide(color: p.panelBorder),
          bottom: pos == 0 || pos == 3
              ? BorderSide(color: p.panelBorder)
              : BorderSide.none,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: missing ? 0.5 : 1,
        child: HistoryRow(
          entry: e,
          item: byPath[e.path.toLowerCase()],
          library: widget.library,
          thumbHeight: 54,
          showType: true,
          showProgress: true,
          timeText: missing ? 'Missing' : _when(e),
          onTap: () => _play(e),
          trailing: _menu(e, missing),
        ),
      ),
    );
  }

  Widget _menu(HistoryEntry e, bool missing) => PopupMenuButton<String>(
    tooltip: 'More',
    padding: EdgeInsets.zero,
    icon: Icon(Icons.more_vert, size: 18, color: context.pal.textDim),
    onSelected: (v) {
      switch (v) {
        case 'play':
          _play(e);
        case 'playlist':
          addToPlaylist(context, widget.playlists, [e.path]);
        case final String c when isFileCommand(c):
          runFileCommand(context, c, e.path);
        case 'remove':
          widget.history.removeEntry(e.path);
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'play',
        enabled: !missing,
        child: const Text('Play'),
      ),
      PopupMenuItem(
        value: 'playlist',
        enabled: !missing,
        child: const Text('Add to playlist…'),
      ),
      const PopupMenuItem(value: 'remove', child: Text('Remove from history')),
      if (!missing) ...fileMenuItems(),
    ],
  );
}
