import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/playlist_service.dart';
import '../services/thumbnail_service.dart';
import 'library_thumb.dart';
import 'playlist_dialogs.dart';
import 'theme.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({
    super.key,
    required this.controller,
    required this.playlists,
    required this.thumbnails,
    required this.onAddFiles,
    required this.onAddFolder,
  });

  final NslPlayerController controller;
  final PlaylistService playlists;
  final ThumbnailService thumbnails;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.panelTop, p.panelBottom],
        ),
        border: Border(left: BorderSide(color: p.panelBorder)),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final items = controller.filtered;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Queue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${controller.queue.length} items',
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (final f in QueueFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            QueueFilter.all => 'All',
                            QueueFilter.audio => 'Audio',
                            QueueFilter.video => 'Video',
                          }),
                          selected: controller.filter == f,
                          showCheckmark: false,
                          onSelected: (_) => controller.setFilter(f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing here yet',
                          style: TextStyle(color: p.textDim, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: items.length,
                        itemBuilder: (_, k) {
                          final e = items[k];
                          return _QueueRow(
                            item: e.value,
                            thumbnails: thumbnails,
                            playing: e.key == controller.index,
                            onTap: () => controller.playIndex(e.key),
                            onRemove: () => controller.removeAt(e.key),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.panelBorder)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onAddFiles,
                            child: const Text('Add files'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onAddFolder,
                            child: const Text('Add folder'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: controller.queue.isEmpty
                            ? null
                            : () => saveAsPlaylist(context, playlists, [
                                for (final q in controller.queue) q.path,
                              ]),
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('Save as playlist'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.thumbnails,
    required this.playing,
    required this.onTap,
    required this.onRemove,
  });

  final QueueItem item;
  final ThumbnailService thumbnails;
  final bool playing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: playing ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: playing
              ? BorderSide(color: p.accent.withValues(alpha: 0.35))
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: p.track,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: PathThumb(
                      path: item.path,
                      thumbnails: thumbnails,
                      iconSize: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
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
                            fontWeight: FontWeight.w500,
                            color: playing ? p.accentInk : p.text,
                          ),
                        ),
                        Text(
                          item.isVideo ? 'Video' : 'Audio',
                          style: TextStyle(fontSize: 12, color: p.textDim),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    iconSize: 16,
                    color: p.textDim,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
