import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/library_service.dart';
import '../services/playlist_service.dart';
import 'controls.dart';
import 'library_items.dart';
import 'playlist_dialogs.dart';
import 'theme.dart';

/// The Library section: scanned folders with search, filter and sorting.
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.library,
    required this.playlists,
    required this.controller,
    required this.onOpenPlayer,
  });

  final LibraryService library;
  final PlaylistService playlists;
  final NslPlayerController controller;
  final VoidCallback onOpenPlayer;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _search = TextEditingController();
  bool? _video; // null = all
  String? _folder; // null = all saved folders
  LibrarySort _sort = LibrarySort.title;

  /// Selection mode: tapping rows picks them instead of playing.
  bool _selecting = false;
  final Set<String> _selected = {};

  LibraryService get lib => widget.library;

  void _setSelecting(bool v) => setState(() {
    _selecting = v;
    if (!v) _selected.clear();
  });

  void _toggle(String path) => setState(() {
    if (!_selected.remove(path)) _selected.add(path);
  });

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _enqueue(List<String> paths) async {
    await widget.controller.addPaths(paths);
    if (mounted) {
      _toast(
        'Added ${paths.length} ${paths.length == 1 ? 'file' : 'files'} '
        'to the queue.',
      );
    }
  }

  Future<void> _toPlaylist(List<String> paths) =>
      addToPlaylist(context, widget.playlists, paths);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final added = await lib.addFolder(dir);
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That folder is already saved.')),
      );
    }
  }

  /// Plays the visible list starting at [index].
  Future<void> _play(List<LibraryItem> shown, int index) async {
    await widget.controller.openPaths([
      for (final i in shown) i.path,
    ], start: index);
    widget.onOpenPlayer();
  }

  static const _sortLabels = {
    LibrarySort.title: 'Title',
    LibrarySort.artist: 'Artist',
    LibrarySort.album: 'Album',
    LibrarySort.recent: 'Recently added',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final shown = lib.query(
          query: _search.text,
          video: _video,
          folder: _folder,
          sort: _sort,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
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
                          'Library',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lib.folders.isEmpty
                              ? 'Add a folder to build your library.'
                              : '${lib.musicCount} songs · ${lib.videoCount} videos'
                                    ' in ${lib.folders.length} '
                                    '${lib.folders.length == 1 ? 'folder' : 'folders'}',
                          style: TextStyle(fontSize: 14, color: p.textDim),
                        ),
                      ],
                    ),
                  ),
                  if (lib.folders.isNotEmpty)
                    IconBtn(
                      Icons.refresh,
                      lib.scanning ? () {} : lib.scan,
                      tooltip: 'Rescan folders',
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('Add folder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ],
              ),
              if (lib.scanning) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: lib.scanTotal == 0
                      ? null
                      : lib.scanned / lib.scanTotal,
                  minHeight: 3,
                  color: p.accent,
                  backgroundColor: p.track,
                ),
                const SizedBox(height: 4),
                Text(
                  lib.scanTotal == 0
                      ? 'Looking for files…'
                      : 'Reading ${lib.scanned} of ${lib.scanTotal}',
                  style: TextStyle(fontSize: 12, color: p.textDim),
                ),
              ],
              if (lib.folders.isNotEmpty) _folderChips(p),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search title, artist, album',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(_search.clear),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  SegmentedButton<bool?>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: null, label: Text('All')),
                      ButtonSegment(value: false, label: Text('Music')),
                      ButtonSegment(value: true, label: Text('Videos')),
                    ],
                    selected: {_video},
                    onSelectionChanged: (v) => setState(() => _video = v.first),
                  ),
                  DropdownButton<LibrarySort>(
                    value: _sort,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final e in _sortLabels.entries)
                        DropdownMenuItem(
                          value: e.key,
                          child: Text('Sort: ${e.value}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _sort = v ?? _sort),
                  ),
                  FilterChip(
                    label: const Text('Select'),
                    avatar: const Icon(Icons.checklist, size: 16),
                    selected: _selecting,
                    showCheckmark: false,
                    onSelected: _setSelecting,
                  ),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_list, size: 18),
                        tooltip: 'List',
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.grid_view, size: 18),
                        tooltip: 'Grid',
                      ),
                    ],
                    selected: {lib.gridView},
                    onSelectionChanged: (v) => lib.gridView = v.first,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          lib.items.isEmpty
                              ? (lib.scanning ? '' : 'Your library is empty.')
                              : 'No matches.',
                          style: TextStyle(fontSize: 13, color: p.textDim),
                        ),
                      )
                    : lib.gridView
                    ? GridView.builder(
                        // Only the tiles on screen are built, so only those
                        // ask for thumbnails.
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisExtent: 196,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => LibraryTile(
                          item: shown[i],
                          library: lib,
                          actions: _actionsFor(shown, i),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemExtent: 60,
                        itemBuilder: (_, i) => LibraryRow(
                          item: shown[i],
                          library: lib,
                          actions: _actionsFor(shown, i),
                        ),
                      ),
              ),
              if (_selecting) _actionBar(p, shown),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// What a row / tile does, shared by the list and the grid.
  ItemActions _actionsFor(List<LibraryItem> shown, int i) {
    final path = shown[i].path;
    return ItemActions(
      playing: path == widget.controller.currentPath,
      selecting: _selecting,
      selected: _selected.contains(path),
      onTap: () => _selecting ? _toggle(path) : _play(shown, i),
      onAddToQueue: () => _enqueue([path]),
      onAddToPlaylist: () => _toPlaylist([path]),
      onSelect: () {
        setState(() => _selecting = true);
        _toggle(path);
      },
    );
  }

  /// Bar shown in selection mode: act on every picked file (any folder).
  Widget _actionBar(NslPalette p, List<LibraryItem> shown) {
    // Keep the order the list shows, and ignore picks hidden by a new filter.
    final picked = [
      for (final i in shown)
        if (_selected.contains(i.path)) i.path,
    ];
    final hidden = _selected.length - picked.length;
    final allShown = shown.isNotEmpty && picked.length == shown.length;
    final enabled = picked.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: p.panelTop,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.panelBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${picked.length} selected'
            '${hidden > 0 ? ' (+$hidden hidden by filter)' : ''}',
            style: TextStyle(fontSize: 13, color: p.text),
          ),
          TextButton(
            onPressed: () => setState(() {
              if (allShown) {
                _selected.removeAll(picked);
              } else {
                _selected.addAll(shown.map((i) => i.path));
              }
            }),
            child: Text(allShown ? 'Clear shown' : 'Select all shown'),
          ),
          FilledButton.icon(
            onPressed: enabled
                ? () async {
                    await _toPlaylist(picked);
                    if (mounted) _setSelecting(false);
                  }
                : null,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Add to playlist'),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
            ),
          ),
          OutlinedButton.icon(
            onPressed: enabled
                ? () async {
                    await _enqueue(picked);
                    if (mounted) _setSelecting(false);
                  }
                : null,
            icon: const Icon(Icons.queue_music, size: 18),
            label: const Text('Add to queue'),
          ),
          TextButton(
            onPressed: () => _setSelecting(false),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Saved folders: tap one to see only its files, tap again (or "All
  /// folders") to see everything. The x removes it from the library.
  Widget _folderChips(NslPalette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ChoiceChip(
            label: Text(
              'All folders (${lib.items.length})',
              style: const TextStyle(fontSize: 12),
            ),
            selected: _folder == null,
            onSelected: (_) => setState(() => _folder = null),
          ),
          for (final f in lib.folders)
            Tooltip(
              message: f,
              child: InputChip(
                label: Text(
                  '${LibraryService.folderName(f)} (${lib.countIn(f)})',
                  style: const TextStyle(fontSize: 12),
                ),
                avatar: const Icon(Icons.folder_outlined, size: 16),
                selected: _folder == f,
                showCheckmark: false,
                onSelected: (_) =>
                    setState(() => _folder = _folder == f ? null : f),
                onDeleted: () {
                  if (_folder == f) _folder = null;
                  lib.removeFolder(f);
                },
                deleteButtonTooltipMessage: 'Remove folder from library',
              ),
            ),
        ],
      ),
    );
  }
}
