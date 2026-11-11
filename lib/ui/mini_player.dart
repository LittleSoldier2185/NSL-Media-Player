import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/legacy.dart';

import '../player_controller/player_controller.dart';
import 'controls.dart';
import 'theme.dart';

/// Window size for the picture-in-picture mini player: the picture fills the
/// whole window, so the window takes the video's shape (like Chrome / Edge
/// picture-in-picture). Landscape videos are 420px wide; portrait ones are
/// 480px tall. Extreme shapes are limited so the controls still fit.
Size miniVideoSize(double aspect) {
  const longSide = 420.0;
  if (aspect.isNaN || aspect <= 0) aspect = 16 / 9;
  if (aspect >= 1) {
    final h = (longSide / aspect).clamp(180.0, longSide);
    return Size(longSide, h.roundToDouble());
  }
  const maxHeight = 480.0;
  final w = (maxHeight * aspect).clamp(270.0, longSide);
  return Size(w.roundToDouble(), maxHeight);
}

/// Mini player. A video is shown picture-in-picture style (picture fills the
/// window, controls appear over it while the mouse is on it); audio uses the
/// small card from the "Mini player" board of the UI design.
///
/// The window itself is resized / made always-on-top / made translucent by
/// the page that shows this widget.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.opacity,
    required this.onTop,
    required this.onOpacity,
    required this.onToggleOnTop,
    required this.onToggleVideo,
    required this.onExpand,
  });

  final NslPlayerController controller;
  final int opacity;
  final bool onTop;
  final ValueChanged<int> onOpacity;
  final VoidCallback onToggleOnTop;

  /// Switches between picture + sound and sound only (lighter on CPU/GPU).
  final VoidCallback onToggleVideo;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.showVideo
          ? _PipView(
              controller: controller,
              opacity: opacity,
              onTop: onTop,
              onOpacity: onOpacity,
              onToggleOnTop: onToggleOnTop,
              onToggleVideo: onToggleVideo,
              onExpand: onExpand,
            )
          : _card(context),
    );
  }

  // ---- audio card ----

  Widget _card(BuildContext context) {
    final p = context.pal;
    final pl = controller.player;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.panelTop, p.panelBottom],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row (drag area + window buttons)
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.panelBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'NSL MINI',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: p.icon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: onTop ? 'Unpin from top' : 'Keep on top',
                  onPressed: onToggleOnTop,
                  color: onTop ? p.accentInk : p.icon,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(onTop ? Icons.push_pin : Icons.push_pin_outlined),
                ),
                if (controller.isVideoFile)
                  IconBtn(
                    controller.audioOnly
                        ? Icons.videocam_off_outlined
                        : Icons.videocam_outlined,
                    onToggleVideo,
                    tooltip: controller.audioOnly
                        ? 'Show video'
                        : 'Sound only (saves CPU)',
                  ),
                IconBtn(Icons.open_in_full, onExpand, tooltip: 'Full player'),
                IconBtn(
                  Icons.close,
                  () => windowManager.close(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          // Now playing
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: p.track,
                    border: Border.all(color: p.border),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accent.withValues(alpha: 0.45),
                    ),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.title.isEmpty
                            ? 'Nothing playing'
                            : controller.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      Text(
                        controller.current == null
                            ? ''
                            : (controller.isVideoFile ? 'Video' : 'Audio'),
                        style: TextStyle(fontSize: 12, color: p.icon),
                      ),
                    ],
                  ),
                ),
                IconBtn(
                  Icons.skip_previous,
                  controller.previous,
                  tooltip: 'Previous',
                ),
                StreamBuilder<bool>(
                  stream: pl.stream.playing,
                  initialData: pl.state.playing,
                  builder: (_, s) => PlayButton(
                    playing: s.data ?? false,
                    onTap: controller.togglePlay,
                    size: 44,
                  ),
                ),
                IconBtn(Icons.skip_next, controller.next, tooltip: 'Next'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SeekRow(controller: controller),
          ),
          // Opacity
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: p.track,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  'Opacity',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: p.icon,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: p.icon,
                      inactiveTrackColor: p.border,
                      thumbColor: p.text,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      min: 20,
                      max: 100,
                      value: opacity.toDouble(),
                      onChanged: (v) => onOpacity(v.round()),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$opacity%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: p.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _mmss(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

/// Picture-in-picture view: the video fills the window. Click toggles
/// play / pause, dragging anywhere on the picture moves the window, and the
/// controls fade in over it while the mouse is on it (or while paused).
class _PipView extends StatefulWidget {
  const _PipView({
    required this.controller,
    required this.opacity,
    required this.onTop,
    required this.onOpacity,
    required this.onToggleOnTop,
    required this.onToggleVideo,
    required this.onExpand,
  });

  final NslPlayerController controller;
  final int opacity;
  final bool onTop;
  final ValueChanged<int> onOpacity;
  final VoidCallback onToggleOnTop;
  final VoidCallback onToggleVideo;
  final VoidCallback onExpand;

  @override
  State<_PipView> createState() => _PipViewState();
}

class _PipViewState extends State<_PipView> {
  bool _hover = false;

  NslPlayerController get c => widget.controller;

  Widget _icon(
    IconData icon,
    VoidCallback onTap,
    String tooltip, {
    Color color = Colors.white,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    color: color,
    icon: Icon(icon, shadows: const [Shadow(blurRadius: 4)]),
  );

  Widget _fade(bool show, Widget child) => AnimatedOpacity(
    opacity: show ? 1 : 0,
    duration: const Duration(milliseconds: 150),
    child: IgnorePointer(ignoring: !show, child: child),
  );

  static const _scrimTop = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xCC000000), Color(0x00000000)],
    ),
  );
  static const _scrimBottom = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xDD000000), Color(0x00000000)],
    ),
  );

  Widget _opacityMenu() {
    var v = widget.opacity;
    return PopupMenuButton<int>(
      tooltip: 'Opacity',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: const Icon(
        Icons.opacity,
        size: 18,
        color: Colors.white,
        shadows: [Shadow(blurRadius: 4)],
      ),
      itemBuilder: (_) => [
        PopupMenuItem<int>(
          enabled: false, // so dragging the slider does not close the menu
          child: StatefulBuilder(
            builder: (context, setLocal) => SizedBox(
              width: 220,
              child: Row(
                children: [
                  const Icon(Icons.opacity, size: 16),
                  Expanded(
                    child: Slider(
                      min: 20,
                      max: 100,
                      value: v.toDouble(),
                      onChanged: (x) {
                        setLocal(() => v = x.round());
                        widget.onOpacity(v);
                      },
                    ),
                  ),
                  SizedBox(width: 40, child: Text('$v%')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pl = c.player;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
        color: Colors.black,
      ),
      clipBehavior: Clip.antiAlias,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: StreamBuilder<bool>(
          stream: pl.stream.playing,
          initialData: pl.state.playing,
          builder: (context, snap) {
            final playing = snap.data ?? false;
            final show = _hover || !playing;
            return Stack(
              fit: StackFit.expand,
              children: [
                // Picture: click = play/pause, drag = move the window.
                DragToMoveArea(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: c.togglePlay,
                    child: Video(
                      controller: c.video,
                      controls: NoVideoControls,
                    ),
                  ),
                ),
                // Top: title + window buttons
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _fade(
                    show,
                    Container(
                      decoration: _scrimTop,
                      padding: const EdgeInsets.fromLTRB(12, 2, 4, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: DragToMoveArea(
                              child: SizedBox(
                                height: 36,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    c.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                      shadows: [Shadow(blurRadius: 4)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _icon(
                            widget.onTop
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            widget.onToggleOnTop,
                            widget.onTop ? 'Unpin from top' : 'Keep on top',
                            color: widget.onTop ? p.accent : Colors.white,
                          ),
                          _opacityMenu(),
                          _icon(
                            Icons.videocam_off_outlined,
                            widget.onToggleVideo,
                            'Sound only (saves CPU)',
                          ),
                          _icon(
                            Icons.open_in_full,
                            widget.onExpand,
                            'Full player',
                          ),
                          _icon(
                            Icons.close,
                            () => windowManager.close(),
                            'Close',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom: seek bar + transport
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _fade(
                    show,
                    Container(
                      decoration: _scrimBottom,
                      padding: const EdgeInsets.fromLTRB(12, 18, 12, 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PipSeek(controller: c, accent: p.accent),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _icon(
                                Icons.skip_previous,
                                c.previous,
                                'Previous',
                              ),
                              IconButton(
                                tooltip: playing ? 'Pause' : 'Play',
                                onPressed: c.togglePlay,
                                iconSize: 30,
                                color: Colors.white,
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  shadows: const [Shadow(blurRadius: 6)],
                                ),
                              ),
                              _icon(Icons.skip_next, c.next, 'Next'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Thin progress line while the controls are hidden.
                if (!show)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _PipProgressLine(controller: c, color: p.accent),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Seek bar with times, in white for use over the picture.
class _PipSeek extends StatefulWidget {
  const _PipSeek({required this.controller, required this.accent});
  final NslPlayerController controller;
  final Color accent;

  @override
  State<_PipSeek> createState() => _PipSeekState();
}

class _PipSeekState extends State<_PipSeek> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final pl = widget.controller.player;
    const style = TextStyle(
      fontSize: 11,
      color: Colors.white,
      shadows: [Shadow(blurRadius: 4)],
    );
    return StreamBuilder<Duration>(
      stream: pl.stream.duration,
      initialData: pl.state.duration,
      builder: (_, ds) {
        final total = ds.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: pl.stream.position,
          initialData: pl.state.position,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final frac = total.inMilliseconds == 0
                ? 0.0
                : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            final shown = _drag ?? frac;
            return Row(
              children: [
                Text(
                  _mmss(
                    Duration(
                      milliseconds: (shown * total.inMilliseconds).round(),
                    ),
                  ),
                  style: style,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: widget.accent,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: shown.clamp(0.0, 1.0),
                      onChanged: (v) => setState(() => _drag = v),
                      onChangeEnd: (v) {
                        pl.seek(
                          Duration(
                            milliseconds: (v * total.inMilliseconds).round(),
                          ),
                        );
                        setState(() => _drag = null);
                      },
                    ),
                  ),
                ),
                Text(_mmss(total), style: style),
              ],
            );
          },
        );
      },
    );
  }
}

/// 2px playback progress along the bottom edge.
class _PipProgressLine extends StatelessWidget {
  const _PipProgressLine({required this.controller, required this.color});
  final NslPlayerController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pl = controller.player;
    return StreamBuilder<Duration>(
      stream: pl.stream.position,
      initialData: pl.state.position,
      builder: (_, ps) {
        final total = pl.state.duration.inMilliseconds;
        final v = total == 0
            ? 0.0
            : ((ps.data ?? Duration.zero).inMilliseconds / total).clamp(
                0.0,
                1.0,
              );
        return LinearProgressIndicator(
          value: v,
          minHeight: 2,
          color: color,
          backgroundColor: Colors.white24,
        );
      },
    );
  }
}
