import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import '../player_controller/player_controller.dart';
import 'controls.dart';
import 'theme.dart';

/// Mini player card, following the "Mini player" board of the UI design.
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
    required this.onExpand,
  });

  final NslPlayerController controller;
  final int opacity;
  final bool onTop;
  final ValueChanged<int> onOpacity;
  final VoidCallback onToggleOnTop;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
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
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Row(
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
