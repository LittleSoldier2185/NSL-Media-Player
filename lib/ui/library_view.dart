import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/library_service.dart';
import 'controls.dart';
import 'theme.dart';

/// The Library section: scanned folders with search, filter and sorting.
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.library,
    required this.controller,
    required this.onOpenPlayer,
  });

  final LibraryService library;
  final NslPlayerController controller;
  final VoidCallback onOpenPlayer;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _search = TextEditingController();
  bool? _video; // null = all
  LibrarySort _sort = LibrarySort.title;

  LibraryService get lib => widget.library;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) await lib.addFolder(dir);
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
                    : ListView.builder(
                        itemCount: shown.length,
                        itemExtent: 60,
                        itemBuilder: (_, i) => _Row(
                          item: shown[i],
                          library: lib,
                          playing:
                              shown[i].path == widget.controller.currentPath,
                          onTap: () => _play(shown, i),
                        ),
                      ),
              ),
              if (lib.folders.isNotEmpty) _folderChips(p),
            ],
          ),
        );
      },
    );
  }

  Widget _folderChips(NslPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final f in lib.folders)
            InputChip(
              label: Text(f, style: const TextStyle(fontSize: 12)),
              onDeleted: () => lib.removeFolder(f),
              deleteButtonTooltipMessage: 'Remove folder from library',
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.library,
    required this.playing,
    required this.onTap,
  });

  final LibraryItem item;
  final LibraryService library;
  final bool playing;
  final VoidCallback onTap;

  static String _dur(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
        : '${d.inMinutes}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sub = [
      if (item.artist.isNotEmpty) item.artist,
      if (item.album.isNotEmpty) item.album,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: playing ? p.hover : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _Cover(item: item, library: library),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: playing ? p.accentInk : p.text,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                ],
              ),
            ),
            Text(
              _dur(item.durationMs),
              style: TextStyle(fontSize: 12, color: p.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.item, required this.library});
  final LibraryItem item;
  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fallback = Icon(
      item.isVideo ? Icons.movie_outlined : Icons.music_note,
      size: 20,
      color: p.textDim,
    );
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(8),
      ),
      child: item.isVideo
          ? fallback
          : FutureBuilder<Uint8List?>(
              future: library.coverFor(item.path),
              builder: (_, s) {
                final b = s.data;
                if (b == null) return fallback;
                return Image.memory(
                  b,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  cacheWidth: 88,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => fallback,
                );
              },
            ),
    );
  }
}
