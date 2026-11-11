import 'package:flutter/material.dart';

import '../services/library_service.dart';
import 'library_thumb.dart';
import 'theme.dart';

/// What tapping a row / tile and its menu do; built once per item and shared
/// by the list and the grid.
class ItemActions {
  const ItemActions({
    required this.playing,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onSelect,
  });

  final bool playing;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onAddToQueue;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onSelect;
}

String _duration(int ms) {
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
      : '${d.inMinutes}:$s';
}

String _subtitle(LibraryItem item) => [
  if (item.artist.isNotEmpty) item.artist,
  if (item.album.isNotEmpty) item.album,
].join(' · ');

/// "More" menu shared by rows and tiles.
class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.actions, this.iconColor, this.padding});
  final ItemActions actions;
  final Color? iconColor;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      padding: padding ?? const EdgeInsets.all(8),
      icon: Icon(Icons.more_vert, size: 18, color: iconColor),
      onSelected: (v) => switch (v) {
        'queue' => actions.onAddToQueue(),
        'playlist' => actions.onAddToPlaylist(),
        _ => actions.onSelect(),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'queue', child: Text('Add to queue')),
        PopupMenuItem(value: 'playlist', child: Text('Add to playlist…')),
        PopupMenuItem(value: 'select', child: Text('Select…')),
      ],
    );
  }
}

/// One line of the list view.
class LibraryRow extends StatelessWidget {
  const LibraryRow({
    super.key,
    required this.item,
    required this.library,
    required this.actions,
  });

  final LibraryItem item;
  final LibraryService library;
  final ItemActions actions;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sub = _subtitle(item);
    return InkWell(
      onTap: actions.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: actions.selected
              ? p.accent.withValues(alpha: 0.14)
              : actions.playing
              ? p.hover
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (actions.selecting)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Checkbox(
                  value: actions.selected,
                  onChanged: (_) => actions.onTap(),
                ),
              ),
            Container(
              width: 44,
              height: 44,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: LibraryThumb(item: item, library: library),
            ),
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
                      color: actions.playing ? p.accentInk : p.text,
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
              _duration(item.durationMs),
              style: TextStyle(fontSize: 12, color: p.textDim),
            ),
            if (!actions.selecting)
              _ItemMenu(actions: actions, iconColor: p.textDim),
          ],
        ),
      ),
    );
  }
}

/// One card of the grid view: a 16:9 picture with the title underneath.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.item,
    required this.library,
    required this.actions,
  });

  final LibraryItem item;
  final LibraryService library;
  final ItemActions actions;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sub = _subtitle(item);
    final dur = _duration(item.durationMs);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: actions.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: actions.selected
                  ? p.accent
                  : actions.playing
                  ? p.accent.withValues(alpha: 0.5)
                  : p.panelBorder,
              width: actions.selected ? 2 : 1,
            ),
            color: actions.selected
                ? p.accent.withValues(alpha: 0.10)
                : actions.playing
                ? p.hover
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Square album art is shown whole; video frames fill the box.
                    LibraryThumb(
                      item: item,
                      library: library,
                      fit: item.isVideo ? BoxFit.cover : BoxFit.contain,
                      iconSize: 32,
                    ),
                    if (dur.isNotEmpty)
                      Positioned(right: 6, bottom: 6, child: _Badge(text: dur)),
                    if (actions.selecting)
                      Positioned(
                        left: 2,
                        top: 2,
                        child: Checkbox(
                          value: actions.selected,
                          onChanged: (_) => actions.onTap(),
                        ),
                      )
                    else
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _ItemMenu(
                          actions: actions,
                          iconColor: Colors.white,
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: actions.playing ? p.accentInk : p.text,
                      ),
                    ),
                    Text(
                      sub.isEmpty ? (item.isVideo ? 'Video' : 'Audio') : sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: p.textDim),
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

/// Small dark label (duration) drawn over a picture.
class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ),
    );
  }
}
