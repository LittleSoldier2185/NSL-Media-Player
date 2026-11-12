import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/thumbnail_service.dart';
import 'controls.dart';
import 'library_thumb.dart';
import 'theme.dart';

/// The playing bar at the bottom of every page but the player: what is
/// playing, the main controls and the position. It lets music or a video (as
/// sound only) play on while you look at pictures or read.
class NowPlayingDock extends StatelessWidget {
  const NowPlayingDock({
    super.key,
    required this.controller,
    required this.thumbnails,
    required this.onOpenPlayer,
  });

  final NslPlayerController controller;
  final ThumbnailService thumbnails;

  /// Opens the player page (also how a video's picture comes back).
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final path = controller.currentPath;
        if (path == null) return const SizedBox.shrink();
        final p = context.pal;
        final pl = controller.player;
        final isVideo = controller.isVideoFile;
        final sub = !isVideo
            ? 'Music · keeps playing while you browse'
            : controller.audioOnly
            ? 'Video · sound only'
            : 'Video';
        return LayoutBuilder(
          builder: (context, box) {
            final compact = box.maxWidth < 860;
            return Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.panelTop, p.panelBottom],
                ),
                border: Border(top: BorderSide(color: p.panelBorder)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PathThumb(
                        key: ValueKey(path),
                        path: path,
                        thumbnails: thumbnails,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: compact ? 130 : 230,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                          ),
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.textDim),
                        ),
                      ],
                    ),
                  ),
                  IconBtn(
                    Icons.skip_previous,
                    controller.previous,
                    tooltip: 'Previous (P)',
                  ),
                  StreamBuilder<bool>(
                    stream: pl.stream.playing,
                    initialData: pl.state.playing,
                    builder: (_, s) => PlayButton(
                      playing: s.data ?? false,
                      onTap: controller.togglePlay,
                      size: 38,
                    ),
                  ),
                  IconBtn(
                    Icons.skip_next,
                    controller.next,
                    tooltip: 'Next (N)',
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: SeekRow(controller: controller)),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    StreamBuilder<double>(
                      stream: pl.stream.volume,
                      initialData: pl.state.volume,
                      builder: (_, s) {
                        final v = s.data ?? 100;
                        return Row(
                          children: [
                            IconBtn(
                              v == 0 ? Icons.volume_off : Icons.volume_up,
                              controller.toggleMute,
                            ),
                            SizedBox(
                              width: 80,
                              child: NslSlider(
                                value: v / 100,
                                color: p.icon,
                                onChanged: (x) => controller.setVolume(x * 100),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (isVideo && controller.audioOnly)
                    TextButton(
                      onPressed: onOpenPlayer,
                      child: const Text('Show picture'),
                    ),
                  IconBtn(
                    Icons.open_in_full,
                    onOpenPlayer,
                    tooltip: 'Open player',
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
