import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/mini_ipc.dart';
import '../services/playlist_service.dart';
import '../services/random_picker.dart';
import '../services/thumbnail_service.dart';
import 'controls.dart';
import 'history_view.dart';
import 'home_sections.dart';
import 'library_thumb.dart';
import 'library_view.dart';
import 'playlists_view.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'time_format.dart';

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
    required this.onOpenHistory,
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

  /// "See all history".
  final VoidCallback onOpenHistory;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// The three views of Home.
enum HomeTab { all, videos, music }

class _HomePageState extends State<HomePage> {
  bool _table = false;
  int? _hover;
  HomeTab _tab = HomeTab.all;

  /// The random picks stay the same across rebuilds until rolled again.
  late final RandomVideoModel _random = RandomVideoModel(
    items: () => widget.library.items,
    played: widget.history.playedPaths,
  );

  @override
  void dispose() {
    _random.dispose();
    super.dispose();
  }

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
            NavDest.history => HistoryView(
              history: widget.history,
              library: widget.library,
              playlists: widget.playlists,
              controller: widget.controller,
              onOpenPlayer: widget.onOpenPlayer,
              onResume: widget.onResume,
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

  /// Lower-cased path -> library entry, rebuilt on every build of the page
  /// (gives the history rows their tags).
  Map<String, LibraryItem> _byPath = {};

  Widget _homeScroll(NslPalette p) {
    _byPath = {for (final i in widget.library.items) i.path.toLowerCase(): i};
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              const gap = SizedBox(height: 34);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(p, w),
                  const SizedBox(height: 22),
                  _tabs(p),
                  const SizedBox(height: 30),
                  ...switch (_tab) {
                    HomeTab.all => [
                      _continue(p, w, HomeTab.all),
                      gap,
                      _lucky(p, w),
                      gap,
                      ..._musicPreview(p, w, gap),
                      _recent(
                        p,
                        w,
                        video: true,
                        title: 'Recently added videos',
                      ),
                      gap,
                      _historySection(p, 5, HomeTab.all, 'History'),
                      gap,
                      _stats(p, w),
                    ],
                    HomeTab.videos => [
                      _continue(p, w, HomeTab.videos),
                      gap,
                      _randomVideos(p, w),
                      gap,
                      _recent(
                        p,
                        w,
                        video: true,
                        title: 'Recently added',
                        rows: 2,
                      ),
                      gap,
                      _historySection(p, 4, HomeTab.videos, 'Video history'),
                    ],
                    HomeTab.music => [
                      _musicActions(p),
                      const SizedBox(height: 30),
                      _continue(p, w, HomeTab.music),
                      gap,
                      _albums(p, w, rows: 2),
                      gap,
                      _songs(p, w),
                      gap,
                      _historySection(p, 3, HomeTab.music, 'Listening history'),
                    ],
                  },
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ---- header and tabs ----

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

  Widget _link(NslPalette p, String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    child: Text(label, style: TextStyle(color: p.accentInk, fontSize: 13)),
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

  /// All / Videos / Music, with how many of each the Library holds.
  Widget _tabs(NslPalette p) {
    final lib = widget.library;
    Widget tab(HomeTab t, String label, int count) {
      final on = _tab == t;
      return InkWell(
        onTap: () => setState(() => _tab = t),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? p.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: on ? p.accentInk : p.icon,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 11.5, color: p.textDim),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.panelBorder)),
      ),
      child: Row(
        children: [
          tab(HomeTab.all, 'All', 0),
          tab(HomeTab.videos, 'Videos', lib.videoCount),
          tab(HomeTab.music, 'Music', lib.musicCount),
        ],
      ),
    );
  }

  // ---- playing things ----

  Future<void> _playPaths(
    List<String> paths, {
    int start = 0,
    bool shuffle = false,
  }) async {
    if (paths.isEmpty) return;
    final list = shuffle ? ([...paths]..shuffle()) : paths;
    await widget.controller.openPaths(list, start: start);
    widget.onOpenPlayer();
  }

  /// A history row: resume where it stopped, or start over if it had ended.
  void _playEntry(HistoryEntry e) {
    if (e.resumable) {
      widget.onResume(e);
    } else {
      _playPaths([e.path]);
    }
  }

  // ---- Continue ----

  /// Files that were stopped partway, newest first, for the given tab.
  /// Missing files are dropped before counting so the slots stay filled.
  List<HistoryEntry> _resumable(HomeTab tab) => widget.history.resumable
      .where(
        (e) => switch (tab) {
          HomeTab.all => true,
          HomeTab.videos => e.isVideo,
          HomeTab.music => !e.isVideo,
        },
      )
      .where((e) => File(e.path).existsSync())
      .take(_maxContinue)
      .toList();

  /// Most "Continue" entries shown: the big card plus three small ones, which
  /// is what fills the column beside it.
  static const _maxContinue = 4;

  Widget _continue(NslPalette p, double w, HomeTab tab) {
    final items = _resumable(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(p, tab == HomeTab.music ? 'Continue listening' : 'Continue'),
        if (items.isEmpty)
          Text(
            tab == HomeTab.music
                ? 'Nothing to resume yet. Songs you stop partway through show up here.'
                : 'Nothing to resume yet. Files you stop partway through show up here.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else if (tab == HomeTab.music)
          _continueMusic(items, w)
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

  /// Songs have square art, so they get small cards in a row rather than a
  /// big picture card.
  Widget _continueMusic(List<HistoryEntry> items, double w) {
    const gap = 16.0;
    final cols = w >= 900 ? 3 : (w >= 560 ? 2 : 1);
    final cardW = (w - gap * (cols - 1)) / cols;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final e in items.take(cols == 3 ? 3 : cols * 2))
          SizedBox(
            width: cardW,
            child: _MiniResume(
              entry: e,
              thumbnails: widget.library.thumbnails,
              onTap: () => widget.onResume(e),
            ),
          ),
      ],
    );
  }

  // ---- random video and shuffle ----

  /// "Feeling lucky?": a random video, and shuffle buttons for the whole
  /// Library.
  Widget _lucky(NslPalette p, double w) {
    final lib = widget.library;
    final videos = [
      for (final i in lib.items)
        if (i.isVideo) i.path,
    ];
    final songs = [
      for (final i in lib.items)
        if (!i.isVideo) i.path,
    ];
    final random = RandomVideoCard(
      model: _random,
      library: lib,
      onPlay: (i) => _playPaths([i.path]),
      onOpenLibrary: widget.onOpenLibrary,
    );
    final shuffleVideos = ShuffleCard(
      title: 'Shuffle all videos',
      subtitle: videos.isEmpty
          ? 'No videos in your Library yet'
          : '${videos.length} videos in your Library',
      enabled: videos.isNotEmpty,
      onTap: () => _playPaths(videos, shuffle: true),
    );
    final shuffleSongs = ShuffleCard(
      title: 'Shuffle all music',
      subtitle: songs.isEmpty
          ? 'No songs in your Library yet'
          : '${songs.length} songs in your Library',
      enabled: songs.isNotEmpty,
      onTap: () => _playPaths(songs, shuffle: true),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(p, 'Feeling lucky?'),
        if (w >= 900)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: random),
              const SizedBox(width: 20),
              Expanded(child: shuffleVideos),
              const SizedBox(width: 20),
              Expanded(child: shuffleSongs),
            ],
          )
        else ...[
          random,
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: shuffleVideos),
              const SizedBox(width: 16),
              Expanded(child: shuffleSongs),
            ],
          ),
        ],
      ],
    );
  }

  /// The Videos tab: three random videos with the filter and re-roll buttons.
  Widget _randomVideos(NslPalette p, double w) {
    final lib = widget.library;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenableBuilder(
          listenable: _random,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Random videos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Only unwatched'),
                  selected: _random.onlyUnwatched,
                  showCheckmark: false,
                  onSelected: _random.setOnlyUnwatched,
                ),
                OutlinedButton.icon(
                  onPressed: _random.roll,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Roll again'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                  ),
                ),
                FilledButton.icon(
                  onPressed: lib.videoCount == 0
                      ? null
                      : () => _playPaths([
                          for (final i in lib.items)
                            if (i.isVideo) i.path,
                        ], shuffle: true),
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Shuffle all videos'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    minimumSize: const Size(0, 38),
                  ),
                ),
              ],
            ),
          ),
        ),
        RandomVideoGrid(
          model: _random,
          library: lib,
          width: w,
          onPlay: (i) => _playPaths([i.path]),
          onOpenLibrary: widget.onOpenLibrary,
        ),
      ],
    );
  }

  // ---- music ----

  /// Play all / Shuffle, and what the Library holds.
  Widget _musicActions(NslPalette p) {
    final lib = widget.library;
    final count = lib.musicCount;
    List<String> all() => [
      for (final i in lib.query(video: false, sort: LibrarySort.artist)) i.path,
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: count == 0 ? null : () => _playPaths(all()),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text('Play all'),
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: p.onAccent,
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 22),
          ),
        ),
        OutlinedButton.icon(
          onPressed: count == 0 ? null : () => _playPaths(all(), shuffle: true),
          icon: const Icon(Icons.shuffle, size: 18),
          label: const Text('Shuffle'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 22),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          count == 0
              ? 'No songs in your Library yet'
              : '$count songs · ${lib.albums().length} albums · '
                    '${lib.artistCount} artists',
          style: TextStyle(fontSize: 14, color: p.textDim),
        ),
      ],
    );
  }

  int _tileCols(double w, double minTile, {int max = 6}) =>
      ((w + 16) / (minTile + 16)).floor().clamp(2, max);

  /// Albums from the music tags: a preview row on the All tab.
  List<Widget> _musicPreview(NslPalette p, double w, Widget gap) {
    if (widget.library.albums().isEmpty) return const [];
    return [_albums(p, w, rows: 1, compact: true), gap];
  }

  Widget _albums(
    NslPalette p,
    double w, {
    required int rows,
    bool compact = false,
  }) {
    final lib = widget.library;
    final albums = lib.albums();
    final cols = _tileCols(w, 160);
    final tileW = (w - 16 * (cols - 1)) / cols;
    final shown = albums.take(cols * rows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          p,
          compact ? 'Music' : 'Albums',
          trailing: _link(
            p,
            compact ? 'Open Music' : 'See all in Library',
            compact
                ? () => setState(() => _tab = HomeTab.music)
                : widget.onOpenLibrary,
          ),
        ),
        if (shown.isEmpty)
          Text(
            lib.musicCount == 0 ? 'No songs in your Library yet.' : 'No albums found. Albums come from the album tag of your music files.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 18,
            children: [
              for (final a in shown)
                SizedBox(
                  width: tileW,
                  child: AlbumTile(
                    album: a,
                    library: lib,
                    onTap: () => _playPaths([for (final t in a.tracks) t.path]),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// The newest songs as a list.
  Widget _songs(NslPalette p, double w) {
    final lib = widget.library;
    final shown = lib
        .query(video: false, sort: LibrarySort.recent)
        .take(5)
        .toList();
    final paths = [for (final s in shown) s.path];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          p,
          'Recently added songs',
          trailing: _link(p, 'See all in Library', widget.onOpenLibrary),
        ),
        if (shown.isEmpty)
          Text(
            'No songs in your Library yet.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
          Container(
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
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.panelBorder),
                  SongRow(
                    number: i + 1,
                    item: shown[i],
                    library: lib,
                    showAlbum: w >= 700,
                    onTap: () => _playPaths(paths, start: i),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ---- history ----

  /// The newest played files (any file still on disk), as a short list.
  Widget _historySection(NslPalette p, int limit, HomeTab tab, String title) {
    final rows = <Widget>[];
    for (final e in widget.history.entries) {
      if (rows.length >= limit) break;
      if (tab == HomeTab.videos && !e.isVideo) continue;
      if (tab == HomeTab.music && e.isVideo) continue;
      if (!File(e.path).existsSync()) continue;
      if (rows.isNotEmpty) rows.add(Divider(height: 1, color: p.panelBorder));
      rows.add(
        HistoryRow(
          entry: e,
          item: _byPath[e.path.toLowerCase()],
          library: widget.library,
          showType: tab == HomeTab.all,
          onTap: () => _playEntry(e),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          p,
          title,
          trailing: _link(p, 'See all history', widget.onOpenHistory),
        ),
        if (rows.isEmpty)
          Text(
            'Nothing played yet.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
          Container(
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
            child: Column(children: rows),
          ),
      ],
    );
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

  /// The newest files of the Library, as many as fit in [rows] rows.
  Widget _recent(
    NslPalette p,
    double w, {
    required bool video,
    required String title,
    int rows = 1,
  }) {
    final lib = widget.library;
    final trailing = _link(
      p,
      lib.items.isEmpty ? 'Open Library' : 'See all in Library',
      widget.onOpenLibrary,
    );
    if (lib.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(p, title, trailing: trailing),
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
    final cols = _tileCols(w, 176);
    final tileW = (w - gap * (cols - 1)) / cols;
    final shown = lib
        .query(video: video, sort: LibrarySort.recent)
        .take(cols * rows)
        .toList();
    final paths = [for (final i in shown) i.path];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(p, title, trailing: trailing),
        if (shown.isEmpty)
          Text(
            video
                ? 'No videos in your Library yet.'
                : 'No songs in your Library yet.',
            style: TextStyle(fontSize: 13, color: p.textDim),
          )
        else
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
                    onTap: () => _playPaths(paths, start: i),
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
                      '${progressText(entry)} · ${agoText(entry.lastPlayed)}',
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
                      progressText(entry),
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
