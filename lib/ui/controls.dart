import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import 'file_menu.dart';
import 'quick_settings.dart';
import 'theme.dart';

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

const _tabular = [FontFeature.tabularFigures()];

class ControlsBar extends StatelessWidget {
  const ControlsBar({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onFullscreen,
    required this.onSettings,
    required this.onToggleQueue,
    required this.onMini,
  });

  final NslPlayerController controller;
  final VoidCallback onOpen;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onToggleQueue;
  final VoidCallback onMini;

  @override
  Widget build(BuildContext context) {
    final p = controller.player;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [context.pal.panelTop, context.pal.panelBottom],
        ),
        border: Border(top: BorderSide(color: context.pal.panelBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SeekRow(controller: controller),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) {
              // Narrow window: drop the volume slider and let the right-hand
              // buttons shrink instead of overflowing.
              final narrow = box.maxWidth < 900;
              return Row(
                children: [
                  StreamBuilder<bool>(
                    stream: p.stream.playing,
                    initialData: p.state.playing,
                    builder: (_, s) => PlayButton(
                      playing: s.data ?? false,
                      onTap: controller.togglePlay,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconBtn(
                    Icons.skip_previous,
                    controller.previous,
                    tooltip: 'Previous (P)',
                  ),
                  IconBtn(
                    Icons.skip_next,
                    controller.next,
                    tooltip: 'Next (N)',
                  ),
                  IconBtn(
                    Icons.replay_5,
                    () => controller.seekRelative(
                      Duration(seconds: -controller.seekStep),
                    ),
                  ),
                  IconBtn(
                    Icons.forward_5,
                    () => controller.seekRelative(
                      Duration(seconds: controller.seekStep),
                    ),
                  ),
                  const SizedBox(width: 12),
                  StreamBuilder<double>(
                    stream: p.stream.volume,
                    initialData: p.state.volume,
                    builder: (_, s) {
                      final v = s.data ?? 100;
                      return Row(
                        children: [
                          IconBtn(
                            v == 0 ? Icons.volume_off : Icons.volume_up,
                            controller.toggleMute,
                          ),
                          if (!narrow)
                            SizedBox(
                              width: 110,
                              child: NslSlider(
                                value: v / 100,
                                color: context.pal.icon,
                                onChanged: (x) => controller.setVolume(x * 100),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          children: [
                            ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) {
                                final p = context.pal;
                                return Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Shuffle',
                                      onPressed: controller.toggleShuffle,
                                      color: controller.shuffle
                                          ? p.accentInk
                                          : p.icon,
                                      icon: const Icon(Icons.shuffle),
                                    ),
                                    IconButton(
                                      tooltip: 'Repeat',
                                      onPressed: controller.cycleRepeat,
                                      color: controller.repeat == NslRepeat.off
                                          ? p.icon
                                          : p.accentInk,
                                      icon: Icon(
                                        controller.repeat == NslRepeat.one
                                            ? Icons.repeat_one
                                            : Icons.repeat,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Audio only',
                                      onPressed: controller.toggleAudioOnly,
                                      color: controller.audioOnly
                                          ? p.accentInk
                                          : p.icon,
                                      icon: const Icon(Icons.headphones),
                                    ),
                                  ],
                                );
                              },
                            ),
                            QuickSettingsButton(controller: controller),
                            IconBtn(
                              Icons.queue_music,
                              onToggleQueue,
                              tooltip: 'Queue',
                            ),
                            IconBtn(
                              Icons.picture_in_picture_alt,
                              onMini,
                              tooltip: 'Mini player (Ctrl+M)',
                            ),
                            ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) {
                                final path = controller.currentPath;
                                return PopupMenuButton<String>(
                                  tooltip: 'Show in folder, copy path or file',
                                  enabled: path != null,
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    Icons.drive_file_move_outlined,
                                    color: context.pal.icon,
                                  ),
                                  onSelected: (v) =>
                                      runFileCommand(context, v, path!),
                                  itemBuilder: (_) =>
                                      fileMenuItems(divider: false),
                                );
                              },
                            ),
                            IconBtn(
                              Icons.folder_open,
                              onOpen,
                              tooltip: 'Open (Ctrl+O)',
                            ),
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
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class SeekRow extends StatefulWidget {
  const SeekRow({super.key, required this.controller});
  final NslPlayerController controller;

  @override
  State<SeekRow> createState() => _SeekRowState();
}

class _SeekRowState extends State<SeekRow> {
  double? _drag; // fraction while dragging

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.player;
    return StreamBuilder<Duration>(
      stream: p.stream.duration,
      initialData: p.state.duration,
      builder: (_, ds) {
        final total = ds.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: p.stream.position,
          initialData: p.state.position,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final frac = total.inMilliseconds == 0
                ? 0.0
                : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            final shown = _drag ?? frac;
            final shownPos = Duration(
              milliseconds: (shown * total.inMilliseconds).round(),
            );
            return Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    _fmt(shownPos),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.pal.icon,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: NslSlider(
                    value: shown,
                    color: context.pal.accent,
                    thumb: true,
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      p.seek(
                        Duration(
                          milliseconds: (v * total.inMilliseconds).round(),
                        ),
                      );
                      setState(() => _drag = null);
                    },
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    _fmt(total),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.pal.textDim,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class NslSlider extends StatelessWidget {
  const NslSlider({
    super.key,
    required this.value,
    required this.color,
    required this.onChanged,
    this.onChangeEnd,
    this.thumb = false,
  });

  final double value;
  final Color color;
  final bool thumb;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: color,
        inactiveTrackColor: context.pal.track,
        thumbColor: context.pal.text,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumb ? 6 : 0),
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({
    super.key,
    required this.playing,
    required this.onTap,
    this.size = 52,
  });
  final double size;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.pal.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.pal.accent.withValues(alpha: 0.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow_rounded,
          size: size / 2,
          color: context.pal.onAccent,
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, this.onTap, {super.key, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 22,
      color: context.pal.icon,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(icon),
    );
  }
}
