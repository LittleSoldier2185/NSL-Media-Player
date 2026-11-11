import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/playlist_service.dart';
import 'controls.dart';
import 'playlist_dialogs.dart';
import 'theme.dart';

/// The Playlists section: saved playlists on the left, the selected one on
/// the right. Files may come from any folder.
class PlaylistsView extends StatefulWidget {
  const PlaylistsView({
    super.key,
    required this.playlists,
    required this.library,
    required this.controller,
    required this.onOpenPlayer,
  });

  final PlaylistService playlists;
  final LibraryService library;
  final NslPlayerController controller;
  final VoidCallback onOpenPlayer;

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  String? _selectedId;

  PlaylistService get svc => widget.playlists;

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _create() async {
    final name = await promptPlaylistName(context);
    if (name == null) return;
    setState(() => _selectedId = svc.create(name).id);
  }

  /// Plays [pl] from [start] (an index into the full list). Files that no
  /// longer exist are skipped.
  Future<void> _play(Playlist pl, {int start = 0}) async {
    final playable = [
      for (final path in pl.paths)
        if (File(path).existsSync()) path,
    ];
    if (playable.isEmpty) {
      _toast('None of the files in this playlist can be found.');
      return;
    }
    // Begin at the chosen item, or the next existing one if it is missing.
    final first = pl.paths.skip(start).where(playable.contains).firstOrNull;
    final startAt = first == null ? 0 : playable.indexOf(first);
    final skipped = pl.paths.length - playable.length;
    await widget.controller.openPaths(playable, start: startAt);
    widget.onOpenPlayer();
    if (skipped > 0) {
      _toast('Skipped $skipped missing ${skipped == 1 ? 'file' : 'files'}.');
    }
  }

  Future<void> _enqueue(Playlist pl) async {
    final playable = [
      for (final p in pl.paths)
        if (File(p).existsSync()) p,
    ];
    if (playable.isEmpty) {
      _toast('None of the files in this playlist can be found.');
      return;
    }
    await widget.controller.addPaths(playable);
    _toast('Added ${playable.length} to the queue.');
  }

  Future<void> _rename(Playlist pl) async {
    final name = await promptPlaylistName(
      context,
      title: 'Rename playlist',
      confirm: 'Rename',
      initial: pl.name,
    );
    if (name != null) svc.rename(pl.id, name);
  }

  Future<void> _delete(Playlist pl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${pl.name}"?'),
        content: const Text(
          'Only the playlist is removed. Your files are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      svc.delete(pl.id);
      if (_selectedId == pl.id) setState(() => _selectedId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final selected = _selectedId == null ? null : svc.byId(_selectedId!);
        return Row(
          children: [
            _list(p, selected),
            Expanded(
              child: selected == null
                  ? Center(
                      child: Text(
                        svc.all.isEmpty
                            ? 'No playlists yet.\nCreate one, or save the queue '
                                  'from the player, or add files from the Library.'
                            : 'Select a playlist.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: p.textDim),
                      ),
                    )
                  : _detail(p, selected),
            ),
          ],
        );
      },
    );
  }

  Widget _list(NslPalette p, Playlist? selected) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: p.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Playlists',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New playlist'),
            style: FilledButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: p.onAccent,
              minimumSize: const Size(0, 44),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final pl in svc.all)
                  Material(
                    color: pl.id == selected?.id ? p.hover : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selectedId = pl.id),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.queue_music,
                              size: 20,
                              color: pl.id == selected?.id
                                  ? p.accentInk
                                  : p.icon,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pl.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: p.text,
                                    ),
                                  ),
                                  Text(
                                    '${pl.paths.length} '
                                    '${pl.paths.length == 1 ? 'file' : 'files'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.textDim,
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(NslPalette p, Playlist pl) {
    // Titles from library tags when the file is in the library.
    final byPath = {
      for (final i in widget.library.items) i.path.toLowerCase(): i,
    };
    final missing = [for (final path in pl.paths) !File(path).existsSync()];
    final missingCount = missing.where((m) => m).length;
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
                      pl.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pl.paths.length} files'
                      '${missingCount > 0 ? ' · $missingCount missing' : ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: missingCount > 0 ? p.accentInk : p.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              IconBtn(
                Icons.drive_file_rename_outline,
                () => _rename(pl),
                tooltip: 'Rename',
              ),
              IconBtn(
                Icons.delete_outline,
                () => _delete(pl),
                tooltip: 'Delete playlist',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: pl.paths.isEmpty ? null : () => _play(pl),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size(0, 44),
                ),
              ),
              OutlinedButton.icon(
                onPressed: pl.paths.isEmpty ? null : () => _enqueue(pl),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Add to queue'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: pl.paths.isEmpty
                ? Center(
                    child: Text(
                      'This playlist is empty.\nAdd files from the Library '
                      '(⋮ menu or Select), or save the queue from the player.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p.textDim),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: pl.paths.length,
                    onReorderItem: (a, b) => svc.move(pl.id, a, b),
                    itemBuilder: (_, i) {
                      final path = pl.paths[i];
                      final item = byPath[path.toLowerCase()];
                      return _TrackRow(
                        key: ValueKey('${pl.id}|$path'),
                        index: i,
                        title:
                            item?.title ??
                            fileNameOf(path)
                                .replaceFirst(RegExp(r'\.[^.]*$'), ''),
                        subtitle: [
                          if (item != null && item.artist.isNotEmpty)
                            item.artist,
                          _parentOf(path),
                        ].join(' · '),
                        isVideo: videoExtensions.contains(extensionOf(path)),
                        missing: missing[i],
                        playing: path == widget.controller.currentPath,
                        onTap: () => _play(pl, start: i),
                        onRemove: () => svc.removeAt(pl.id, i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _parentOf(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.isVideo,
    required this.missing,
    required this.playing,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final String title;
  final String subtitle;
  final bool isVideo;
  final bool missing;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: missing ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: playing ? p.hover : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: p.textDim,
                    ),
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.track,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  missing
                      ? Icons.link_off
                      : isVideo
                      ? Icons.movie_outlined
                      : Icons.music_note,
                  size: 18,
                  color: p.textDim,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: playing ? p.accentInk : p.text,
                      ),
                    ),
                    Text(
                      missing ? 'File not found · $subtitle' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from playlist',
                iconSize: 16,
                color: p.textDim,
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
