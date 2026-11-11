import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/random_picker.dart';
import 'library_thumb.dart';
import 'theme.dart';
import 'time_format.dart';

/// Home page building blocks beyond the first screen: the random video,
/// the shuffle buttons, albums, songs and history rows.

BoxDecoration _cardDecoration(NslPalette p) => BoxDecoration(
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: p.panelBorder),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [p.panelTop, p.panelBottom],
  ),
);

/// A round play button drawn over a picture.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({this.size = 60});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xB80B0C10),
      border: Border.all(color: const Color(0x4DFFFFFF)),
    ),
    child: Icon(
      Icons.play_arrow_rounded,
      size: size * 0.55,
      color: Colors.white,
    ),
  );
}

String _videoMeta(RandomVideoModel model, LibraryItem item) => [
  'Video',
  'added ${agoText(DateTime.fromMillisecondsSinceEpoch(item.modified))}',
  model.wasPlayed(item.path) ? 'played before' : 'never played',
].join(' · ');

/// The big "Random video" card of the All tab.
class RandomVideoCard extends StatelessWidget {
  const RandomVideoCard({
    super.key,
    required this.model,
    required this.library,
    required this.onPlay,
    required this.onOpenLibrary,
  });

  final RandomVideoModel model;
  final LibraryService library;
  final void Function(LibraryItem) onPlay;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        model.ensure();
        if (model.picks.isEmpty) {
          return _EmptyCard(
            message: library.items.isEmpty
                ? 'Add a folder to your Library and a random video from it '
                      'will be offered here.'
                : 'There are no videos in your Library yet.',
            action: 'Open Library',
            onAction: onOpenLibrary,
          );
        }
        final item = model.picks.first;
        final thumb = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => onPlay(item),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LibraryThumb(item: item, library: library, iconSize: 32),
                const Center(child: _PlayBadge()),
              ],
            ),
          ),
        );
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RANDOM VIDEO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.9,
                color: p.accentInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: p.text,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _videoMeta(model, item),
              style: TextStyle(fontSize: 12.5, color: p.textDim),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => onPlay(item),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    minimumSize: const Size(0, 40),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: model.roll,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Roll again'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                ),
                FilterChip(
                  label: const Text('Only unwatched'),
                  selected: model.onlyUnwatched,
                  showCheckmark: false,
                  onSelected: model.setOnlyUnwatched,
                ),
              ],
            ),
            if (model.fellBack)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'You have watched every video, so this pick is from all of them.',
                  style: TextStyle(fontSize: 12, color: p.textDim),
                ),
              ),
          ],
        );
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(p),
          child: LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth >= 560) {
                return Row(
                  children: [
                    SizedBox(width: 268, height: 151, child: thumb),
                    const SizedBox(width: 20),
                    Expanded(child: info),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: thumb),
                  const SizedBox(height: 16),
                  info,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// The three picture cards of the Videos tab's "Random videos" row.
class RandomVideoGrid extends StatelessWidget {
  const RandomVideoGrid({
    super.key,
    required this.model,
    required this.library,
    required this.width,
    required this.onPlay,
    required this.onOpenLibrary,
  });

  final RandomVideoModel model;
  final LibraryService library;
  final double width;
  final void Function(LibraryItem) onPlay;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        model.ensure();
        if (model.picks.isEmpty) {
          return _EmptyCard(
            message: library.items.isEmpty
                ? 'Add a folder to your Library to get random videos.'
                : 'There are no videos in your Library yet.',
            action: 'Open Library',
            onAction: onOpenLibrary,
          );
        }
        const gap = 18.0;
        final cols = width >= 760 ? 3 : (width >= 480 ? 2 : 1);
        final w = (width - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in model.picks.take(cols))
              SizedBox(
                width: w,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onPlay(item),
                    child: Container(
                      decoration: _cardDecoration(p),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 170,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                LibraryThumb(
                                  item: item,
                                  library: library,
                                  iconSize: 32,
                                ),
                                const Center(child: _PlayBadge(size: 52)),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
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
                                  _videoMeta(model, item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
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
              ),
          ],
        );
      },
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.message,
    required this.action,
    required this.onAction,
  });
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(p),
      child: Row(
        children: [
          Icon(Icons.casino_outlined, color: p.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13.5, color: p.textDim),
            ),
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

/// "Shuffle all videos" / "Shuffle all music".
class ShuffleCard extends StatelessWidget {
  const ShuffleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 187),
            padding: const EdgeInsets.all(20),
            decoration: _cardDecoration(p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.track,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shuffle, color: p.accentInk),
                ),
                const SizedBox(height: 18),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: p.textDim),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One album: square cover, name and artist.
class AlbumTile extends StatelessWidget {
  const AlbumTile({
    super.key,
    required this.album,
    required this.library,
    required this.onTap,
  });

  final Album album;
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
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LibraryThumb(
                item: album.cover,
                library: library,
                iconSize: 36,
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          if (album.artist.isNotEmpty)
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.textDim),
            ),
        ],
      ),
    );
  }
}

/// One line of the "Recently added songs" list.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.number,
    required this.item,
    required this.library,
    required this.onTap,
    this.showAlbum = true,
  });

  final int number;
  final LibraryItem item;
  final LibraryService library;
  final VoidCallback onTap;
  final bool showAlbum;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$number',
                style: TextStyle(fontSize: 12.5, color: p.textDim),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: LibraryThumb(item: item, library: library, iconSize: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  if (item.artist.isNotEmpty)
                    Text(
                      item.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                ],
              ),
            ),
            if (showAlbum && item.album.isNotEmpty)
              SizedBox(
                width: 220,
                child: Text(
                  item.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.textDim),
                ),
              ),
            SizedBox(
              width: 52,
              child: Text(
                item.durationMs > 0 ? clockText(item.durationMs) : '',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: p.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One played file in a history list (Home and the History page).
class HistoryRow extends StatelessWidget {
  const HistoryRow({
    super.key,
    required this.entry,
    required this.item,
    required this.library,
    required this.onTap,
    this.thumbHeight = 43,
    this.showType = false,
    this.showProgress = false,
    this.timeText,
    this.trailing,
  });

  final HistoryEntry entry;

  /// The file's library entry, if it is in the Library (gives tags).
  final LibraryItem? item;
  final LibraryService library;
  final VoidCallback onTap;
  final double thumbHeight;
  final bool showType;
  final bool showProgress;

  /// Overrides the relative time ("3 h ago") on the right.
  final String? timeText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isVideo = entry.isVideo;
    final title = item?.title ?? entry.title;
    final finished = !entry.resumable && entry.durMs > 0;
    final String sub;
    if (!isVideo && (item?.artist.isNotEmpty ?? false)) {
      sub = item!.artist;
    } else if (finished) {
      sub = 'Played to the end';
    } else if (entry.posMs > 0) {
      sub = 'Stopped at ${progressText(entry)}';
    } else {
      sub = isVideo ? 'Video' : 'Music';
    }
    final thumbW = isVideo ? thumbHeight * 16 / 9 : thumbHeight;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: thumbW,
              height: thumbHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: PathThumb(
                path: entry.path,
                thumbnails: library.thumbnails,
                modified: item?.modified,
                iconSize: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.textDim),
                  ),
                ],
              ),
            ),
            if (showProgress) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: finished ? 1 : entry.fraction,
                    minHeight: 4,
                    color: p.accent,
                    backgroundColor: p.track,
                  ),
                ),
              ),
            ],
            if (showType) ...[
              const SizedBox(width: 12),
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.track,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  isVideo ? 'Video' : 'Music',
                  style: TextStyle(fontSize: 11.5, color: p.textDim),
                ),
              ),
            ],
            const SizedBox(width: 12),
            SizedBox(
              width: 84,
              child: Text(
                timeText ?? agoText(entry.lastPlayed),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: p.textDim),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
