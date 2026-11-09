import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/media_types.dart';
import 'controls.dart';
import 'theme.dart';

/// Music mode (audio files) and Audio-only mode (video file, no decoding).
/// Follows the "Music + Audio-only" board of the UI design.
class MusicView extends StatelessWidget {
  const MusicView({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onSettings,
    required this.onToggleQueue,
    required this.onMini,
    required this.onFullscreen,
  });

  final NslPlayerController controller;
  final VoidCallback onOpen;
  final VoidCallback onSettings;
  final VoidCallback onToggleQueue;
  final VoidCallback onMini;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pl = controller.player;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.5, -1.2),
          radius: 1.2,
          colors: [Color.lerp(p.bg, p.accent, 0.06)!, p.bg],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              controller.isVideoFile
                  ? _AudioOnlyCard(p: p)
                  : _CoverPlaceholder(p: p),
              const SizedBox(height: 28),
              Text(
                controller.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${extensionOf(controller.currentPath ?? '').toUpperCase()}'
                ' · ${controller.isVideoFile ? 'Video' : 'Audio'}',
                style: TextStyle(fontSize: 14, color: p.textDim),
              ),
              const SizedBox(height: 28),
              SeekRow(controller: controller),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Shuffle',
                      onPressed: controller.toggleShuffle,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      color: controller.shuffle ? p.accentInk : p.textDim,
                      icon: const Icon(Icons.shuffle),
                    ),
                    IconBtn(
                      Icons.skip_previous,
                      controller.previous,
                      tooltip: 'Previous (P)',
                    ),
                    const SizedBox(width: 8),
                    StreamBuilder<bool>(
                      stream: pl.stream.playing,
                      initialData: pl.state.playing,
                      builder: (_, s) => PlayButton(
                        playing: s.data ?? false,
                        onTap: controller.togglePlay,
                        size: 60,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconBtn(
                      Icons.skip_next,
                      controller.next,
                      tooltip: 'Next (N)',
                    ),
                    IconButton(
                      tooltip: 'Repeat',
                      onPressed: controller.cycleRepeat,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      color: controller.repeat == NslRepeat.off
                          ? p.textDim
                          : p.accentInk,
                      icon: Icon(
                        controller.repeat == NslRepeat.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
                            width: 120,
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
                  const Spacer(),
                  if (controller.isVideoFile)
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => OutlinedButton.icon(
                        onPressed: controller.toggleAudioOnly,
                        icon: const Icon(Icons.headphones, size: 18),
                        label: const Text('Audio only'),
                        style: OutlinedButton.styleFrom(
                          shape: const StadiumBorder(),
                          minimumSize: const Size(0, 44),
                          foregroundColor: controller.audioOnly
                              ? p.accentInk
                              : p.icon,
                          side: BorderSide(
                            color: controller.audioOnly
                                ? p.accent.withValues(alpha: 0.5)
                                : p.border,
                          ),
                          backgroundColor: controller.audioOnly
                              ? p.accent.withValues(alpha: 0.12)
                              : null,
                        ),
                      ),
                    ),
                  IconBtn(Icons.queue_music, onToggleQueue, tooltip: 'Queue'),
                  IconBtn(
                    Icons.picture_in_picture_alt,
                    onMini,
                    tooltip: 'Mini player (Ctrl+M)',
                  ),
                  IconBtn(Icons.folder_open, onOpen, tooltip: 'Open (Ctrl+O)'),
                  IconBtn(
                    Icons.settings_outlined,
                    onSettings,
                    tooltip: 'Settings',
                  ),
                  IconBtn(
                    Icons.fullscreen,
                    onFullscreen,
                    tooltip: 'Fullscreen (F)',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.p});
  final NslPalette p;

  @override
  Widget build(BuildContext context) {
    Widget ring(double size, double alpha, Widget? child) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.accent.withValues(alpha: alpha),
      ),
      child: child,
    );
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.panelTop, p.panelBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 64,
            offset: const Offset(0, 32),
            spreadRadius: -12,
          ),
          BoxShadow(
            color: p.accent.withValues(alpha: 0.25),
            blurRadius: 90,
            spreadRadius: -20,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: ring(232, 0.20, ring(148, 0.45, ring(56, 1, null))),
    );
  }
}

class _AudioOnlyCard extends StatelessWidget {
  const _AudioOnlyCard({required this.p});
  final NslPalette p;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: 0.20),
            ),
            child: Icon(Icons.headphones, size: 32, color: p.accentInk),
          ),
          const SizedBox(height: 16),
          Text(
            'Audio only',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Video decoding is off',
            style: TextStyle(fontSize: 13, color: p.textDim),
          ),
        ],
      ),
    );
  }
}
