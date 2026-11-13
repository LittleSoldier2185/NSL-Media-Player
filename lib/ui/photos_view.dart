import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/heic_converter.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/playlist_service.dart';
import '../services/thumbnail_service.dart';
import 'photo_common.dart';
import 'photo_viewer.dart';
import 'library_thumb.dart';
import 'file_menu.dart';
import 'theme.dart';

export 'photo_common.dart'
    show PhotoDay, PhotoFolder, dayLabel, folderAlbums, groupByDay;

enum PhotoTab { timeline, albums, folders }

/// Photos: the timeline of every picture in the library folders, your albums
/// and the folders that hold pictures. Click one to open the viewer.
class PhotosView extends StatefulWidget {
  const PhotosView({
    super.key,
    required this.library,
    required this.albums,
    required this.onOpenLibrary,
    this.controller,
    this.onOpenPlayer,
    this.now,
  });

  final LibraryService library;

  /// Albums you made (named lists of pictures).
  final PlaylistService albums;
  final VoidCallback onOpenLibrary;

  /// The player, to show what is playing under the viewer (none in tests).
  final NslPlayerController? controller;
  final VoidCallback? onOpenPlayer;

  /// "Today" (tests).
  final DateTime Function()? now;

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  final _search = TextEditingController();
  double _tile = 150;
  PhotoTab _tab = PhotoTab.timeline;

  /// An album or a folder that is open (at most one of them).
  String? _albumId;
  String? _folderDir;

  bool _selecting = false;
  final _selected = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _inDetail => _albumId != null || _folderDir != null;

  // ---- what to show ----

  List<LibraryItem> _timelineItems() {
    final q = _search.text.trim().toLowerCase();
    final all = widget.library.visibleImages;
    if (q.isEmpty) return all;
    return [
      for (final i in all)
        if (i.title.toLowerCase().contains(q) ||
            i.path.toLowerCase().contains(q))
          i,
    ];
  }

  LibraryItem _stub(String path) {
    final n = fileNameOf(path);
    final dot = n.lastIndexOf('.');
    return LibraryItem(
      path: path,
      title: dot > 0 ? n.substring(0, dot) : n,
      modified: 0,
    );
  }

  /// The pictures of an album, in the order they were added. A picture that
  /// is no longer in the library folders is still listed (it may be fine on
  /// disk, or gone: the tile then shows a broken picture).
  List<LibraryItem> _albumItems(Playlist a) {
    final by = {for (final i in widget.library.images) i.path.toLowerCase(): i};
    return [for (final p in a.paths) by[p.toLowerCase()] ?? _stub(p)];
  }

  PhotoFolder? _folder(String dir) {
    for (final f in folderAlbums(widget.library.images)) {
      if (f.dir.toLowerCase() == dir.toLowerCase()) return f;
    }
    return null;
  }

  /// The pictures on show (timeline, or the open album / folder).
  List<LibraryItem> _shown() {
    final a = _albumId == null ? null : widget.albums.byId(_albumId!);
    if (a != null) return _albumItems(a);
    final f = _folderDir == null ? null : _folder(_folderDir!);
    if (f != null) return f.items;
    return _timelineItems();
  }

  // ---- actions ----

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) await widget.library.addFolder(dir);
  }

  void _open(List<LibraryItem> list, int index, {bool slideshow = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(
          items: list,
          index: index,
          albums: widget.albums,
          slideshow: slideshow,
          controller: widget.controller,
          thumbnails: widget.library.thumbnails,
          onOpenPlayer: widget.onOpenPlayer,
        ),
      ),
    );
  }

  void _tap(List<LibraryItem> list, int index) {
    final item = list[index];
    if (_selecting) {
      setState(() {
        if (!_selected.remove(item.path)) _selected.add(item.path);
      });
    } else {
      _open(list, index);
    }
  }

  void _endSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _newAlbum() async {
    final name = await askAlbumName(context);
    if (name == null || !mounted) return;
    final a = widget.albums.create(name);
    setState(() {
      _tab = PhotoTab.albums;
      _albumId = a.id;
    });
  }

  Future<void> _renameAlbum(Playlist a) async {
    final name = await askAlbumName(
      context,
      title: 'Rename album',
      initial: a.name,
      action: 'Rename',
    );
    if (name != null) widget.albums.rename(a.id, name);
  }

  Future<void> _deleteAlbum(Playlist a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${a.name}"?'),
        content: const Text(
          'Only the album is deleted. The pictures stay where they are.',
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
    if (ok != true || !mounted) return;
    widget.albums.delete(a.id);
    setState(() => _albumId = null);
  }

  void _removeSelectedFromAlbum(Playlist a) {
    final drop = {for (final p in _selected) p.toLowerCase()};
    for (var i = a.paths.length - 1; i >= 0; i--) {
      if (drop.contains(a.paths[i].toLowerCase())) {
        widget.albums.removeAt(a.id, i);
      }
    }
    _endSelecting();
  }

  void _openTab(PhotoTab t) => setState(() {
    _tab = t;
    _albumId = null;
    _folderDir = null;
    _endSelecting();
  });

  void _back() => setState(() {
    _albumId = null;
    _folderDir = null;
    _endSelecting();
  });

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.library, widget.albums]),
      builder: (context, _) {
        // An open album that was deleted: back to the list.
        if (_albumId != null && widget.albums.byId(_albumId!) == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _back();
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(p),
              const SizedBox(height: 14),
              Expanded(child: _body(p)),
              if (_selecting) _selectionBar(p),
            ],
          ),
        );
      },
    );
  }

  Playlist? get _openAlbum =>
      _albumId == null ? null : widget.albums.byId(_albumId!);

  Widget _header(NslPalette p) {
    final lib = widget.library;
    final album = _openAlbum;
    final folder = _folderDir == null ? null : _folder(_folderDir!);
    final inDetail = _inDetail;
    final title = album?.name ?? folder?.name ?? 'Photos';
    final shown = inDetail ? _shown() : const <LibraryItem>[];
    final count = inDetail
        ? shown.length
        : _tab == PhotoTab.timeline
        ? lib.visibleImages.length
        : 0;
    final canPlay = _showsGrid && shownOrTimeline(shown).isNotEmpty;

    final search = SizedBox(
      width: 200,
      height: 36,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search photos',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: p.track,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: p.border),
          ),
        ),
      ),
    );

    final controls = <Widget>[
      if (!inDetail && _tab == PhotoTab.timeline) search,
      if (_showsGrid)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_size_select_large, size: 16, color: p.icon),
            SizedBox(
              width: 100,
              child: Slider(
                value: _tile,
                min: 90,
                max: 260,
                onChanged: (v) => setState(() => _tile = v),
              ),
            ),
          ],
        ),
      if (!inDetail && _tab == PhotoTab.timeline && lib.duplicateCount > 0)
        Tooltip(
          message: 'Identical copies of a picture. Nothing is deleted.',
          child: OutlinedButton.icon(
            onPressed: () => lib.hideDuplicates = !lib.hideDuplicates,
            icon: Icon(
              lib.hideDuplicates ? Icons.visibility_off : Icons.content_copy,
              size: 18,
            ),
            label: Text(
              lib.hideDuplicates
                  ? 'Hiding ${lib.duplicateCount} duplicates'
                  : 'Show only one of each (${lib.duplicateCount})',
            ),
          ),
        ),
      if (canPlay)
        OutlinedButton.icon(
          onPressed: () => _open(shownOrTimeline(shown), 0, slideshow: true),
          icon: const Icon(Icons.slideshow, size: 18),
          label: const Text('Slideshow'),
        ),
      if (canPlay)
        OutlinedButton(
          onPressed: () =>
              _selecting ? _endSelecting() : setState(() => _selecting = true),
          child: Text(_selecting ? 'Cancel' : 'Select'),
        ),
      if (album != null)
        PopupMenuButton<String>(
          tooltip: 'Album',
          onSelected: (v) =>
              v == 'rename' ? _renameAlbum(album) : _deleteAlbum(album),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete album')),
          ],
        ),
      if (!inDetail && _tab == PhotoTab.timeline)
        FilledButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add folder'),
        ),
      if (!inDetail && _tab == PhotoTab.albums)
        FilledButton.icon(
          onPressed: _newAlbum,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New album'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (inDetail)
              IconButton(
                tooltip: 'Back',
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
              ),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (count > 0)
              Text('$count', style: TextStyle(fontSize: 14, color: p.textDim)),
          ],
        ),
        const SizedBox(height: 10),
        // Tabs on the left, tools on the right; each wraps onto a new line
        // when the window is narrow instead of overflowing.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!inDetail)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final t in PhotoTab.values) _tabChip(p, t)],
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: controls,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Pictures a header button works on: the open album / folder, else the
  /// timeline.
  List<LibraryItem> shownOrTimeline(List<LibraryItem> detail) =>
      _inDetail ? detail : _timelineItems();

  bool get _showsGrid => _inDetail || _tab == PhotoTab.timeline;

  Widget _tabChip(NslPalette p, PhotoTab t) {
    final on = !_inDetail && t == _tab;
    final label = switch (t) {
      PhotoTab.timeline => 'Timeline',
      PhotoTab.albums => 'Albums',
      PhotoTab.folders => 'Folders',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _openTab(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: on ? p.accent : p.track,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? p.onAccent : p.icon,
          ),
        ),
      ),
    );
  }

  Widget _body(NslPalette p) {
    final lib = widget.library;
    if (_inDetail) {
      final list = _shown();
      if (list.isEmpty) {
        return _Message(
          _albumId != null
              ? 'This album is empty. Press Select on the timeline, pick '
                    'pictures and add them here.'
              : 'No pictures in this folder.',
          p: p,
        );
      }
      return _flatGrid(list);
    }
    switch (_tab) {
      case PhotoTab.timeline:
        final list = _timelineItems();
        if (lib.scanning && list.isEmpty) {
          return _Message('Looking through your library folders…', p: p);
        }
        if (list.isEmpty) return _emptyTimeline(p);
        return _timelineGrid(list);
      case PhotoTab.albums:
        return _albumsGrid(p);
      case PhotoTab.folders:
        return _foldersGrid(p);
    }
  }

  Widget _emptyTimeline(NslPalette p) {
    if (_search.text.trim().isNotEmpty) {
      return _Message('No photo matches "${_search.text.trim()}".', p: p);
    }
    if (widget.library.folders.isEmpty) {
      return _Message(
        'Add a folder with pictures and your photos will show up here.',
        p: p,
      );
    }
    return _Message('No pictures found in your library folders.', p: p);
  }

  // ---- grids ----

  int _cacheWidth(BuildContext context) =>
      (_tile * MediaQuery.devicePixelRatioOf(context)).round().clamp(128, 600);

  Widget _tileFor(List<LibraryItem> list, int i, int cacheWidth) {
    final item = list[i];
    return _Tile(
      item: item,
      thumbnails: widget.library.thumbnails,
      cacheWidth: cacheWidth,
      selecting: _selecting,
      selected: _selected.contains(item.path),
      onTap: () => _tap(list, i),
    );
  }

  SliverGridDelegate get _gridDelegate =>
      SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _tile,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      );

  Widget _flatGrid(List<LibraryItem> list) {
    final cw = _cacheWidth(context);
    return CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: _gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, i) => _tileFor(list, i, cw),
            childCount: list.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    );
  }

  Widget _timelineGrid(List<LibraryItem> list) {
    final p = context.pal;
    final days = groupByDay(list);
    final now = (widget.now ?? DateTime.now)();
    final cw = _cacheWidth(context);
    // The viewer moves in the same order as the grid (newest first), which is
    // the order of [list].
    final ordered = [for (final d in days) ...d.items];
    final orderedIndex = {
      for (var i = 0; i < ordered.length; i++) ordered[i].path: i,
    };
    return CustomScrollView(
      slivers: [
        for (final d in days) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    dayLabel(d.day, now),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    d.items.length == 1
                        ? '1 photo'
                        : '${d.items.length} photos',
                    style: TextStyle(fontSize: 12.5, color: p.textDim),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 18),
            sliver: SliverGrid(
              gridDelegate: _gridDelegate,
              delegate: SliverChildBuilderDelegate((context, i) {
                final item = d.items[i];
                return _Tile(
                  item: item,
                  thumbnails: widget.library.thumbnails,
                  cacheWidth: cw,
                  selecting: _selecting,
                  selected: _selected.contains(item.path),
                  onTap: () => _tap(ordered, orderedIndex[item.path]!),
                );
              }, childCount: d.items.length),
            ),
          ),
        ],
      ],
    );
  }

  Widget _albumsGrid(NslPalette p) {
    final albums = [...widget.albums.all]
      ..sort((a, b) => b.updated.compareTo(a.updated));
    if (albums.isEmpty) {
      return _Message(
        'No albums yet. Press New album, or Select pictures on the timeline '
        'and add them to a new album.',
        p: p,
      );
    }
    return CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 270,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.92,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final a = albums[i];
            final items = _albumItems(a);
            return _AlbumCard(
              title: a.name,
              subtitle: a.paths.length == 1
                  ? '1 photo'
                  : '${a.paths.length} photos',
              covers: items.take(3).toList(),
              thumbnails: widget.library.thumbnails,
              onTap: () => setState(() => _albumId = a.id),
            );
          }, childCount: albums.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    );
  }

  Widget _foldersGrid(NslPalette p) {
    final folders = folderAlbums(widget.library.images);
    if (folders.isEmpty) {
      return _Message(
        widget.library.folders.isEmpty
            ? 'Add a folder with pictures and every folder shows up here.'
            : 'No folders with pictures yet.',
        p: p,
      );
    }
    return CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 270,
            mainAxisSpacing: 18,
            crossAxisSpacing: 18,
            childAspectRatio: 0.92,
          ),
          delegate: SliverChildBuilderDelegate((context, i) {
            final f = folders[i];
            return _AlbumCard(
              title: f.name,
              subtitle: f.items.length == 1
                  ? '1 photo'
                  : '${f.items.length} photos',
              covers: f.items.take(3).toList(),
              thumbnails: widget.library.thumbnails,
              onTap: () => setState(() => _folderDir = f.dir),
            );
          }, childCount: folders.length),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    );
  }

  Widget _selectionBar(NslPalette p) {
    final album = _openAlbum;
    return Container(
      height: 56,
      margin: const EdgeInsets.only(bottom: 12, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: p.panelBottom,
        border: Border.all(color: p.panelBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            _selected.isEmpty
                ? 'Pick pictures'
                : '${_selected.length} selected',
            style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
          ),
          const Spacer(),
          if (album != null)
            TextButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => _removeSelectedFromAlbum(album),
              child: const Text('Remove from album'),
            ),
          AddToAlbumButton(
            albums: widget.albums,
            paths: () => _selected.toList(),
            onDone: _endSelecting,
            child: AbsorbPointer(
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : () {},
                icon: const Icon(Icons.photo_album_outlined, size: 18),
                label: const Text('Add to album'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: _endSelecting, child: const Text('Cancel')),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.p});
  final String text;
  final NslPalette p;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_outlined, size: 48, color: p.textDim),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.textDim),
          ),
        ],
      ),
    ),
  );
}

/// A picture tile. Small tiles use the cached 256 px thumbnail (fast to scroll,\n/// and the only way to show HEIC); big ones decode the original.
Widget _thumb(
  LibraryItem item,
  int cacheWidth,
  ThumbnailService thumbs,
  NslPalette p,
) {
  if (cacheWidth <= 300 || HeicConverter.isHeic(item.path)) {
    return PathThumb(
      path: item.path,
      modified: item.modified == 0 ? null : item.modified,
      thumbnails: thumbs,
      fallbackBuilder: (_) =>
          Icon(Icons.broken_image_outlined, size: 22, color: p.textDim),
    );
  }
  return _originalThumb(item.path, cacheWidth, p);
}

Widget _originalThumb(String path, int cacheWidth, NslPalette p) => ColoredBox(
  color: p.track,
  child: Image.file(
    File(path),
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    cacheWidth: cacheWidth,
    filterQuality: FilterQuality.low,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) =>
        Icon(Icons.broken_image_outlined, size: 22, color: p.textDim),
  ),
);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.thumbnails,
    required this.cacheWidth,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final LibraryItem item;
  final ThumbnailService thumbnails;
  final int cacheWidth;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: item.title,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapUp: (d) =>
              showFileContextMenu(context, d.globalPosition, item.path),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _thumb(item, cacheWidth, thumbnails, p),
              ),
              if (selected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.accent, width: 3),
                      color: p.accent.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              if (selecting)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected ? p.accent : Colors.white70,
                    shadows: const [Shadow(blurRadius: 4)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An album or folder: up to three pictures as a collage, then its name and
/// how many pictures it holds.
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.title,
    required this.subtitle,
    required this.covers,
    required this.thumbnails,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<LibraryItem> covers;
  final ThumbnailService thumbnails;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget cell(int i) => i < covers.length
        ? _thumb(covers[i], 360, thumbnails, p)
        : ColoredBox(color: p.track);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: p.panelBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: cell(0)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: cell(1)),
                            const SizedBox(height: 3),
                            Expanded(child: cell(2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
            ),
            Text(subtitle, style: TextStyle(fontSize: 12.5, color: p.textDim)),
          ],
        ),
      ),
    );
  }
}
