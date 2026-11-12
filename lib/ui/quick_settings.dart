import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player_controller/player_controller.dart';
import '../services/sleep_timer.dart';
import 'theme.dart';

/// Lets the user pick a subtitle file and loads it into the player.
Future<void> pickSubtitleFile(NslPlayerController controller) async {
  final r = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt', 'sub'],
  );
  final path = r?.files.single.path;
  if (path != null) await controller.loadSubtitleFile(path);
}

/// Button in the control bar that opens a small panel for the things you want
/// to change while watching: speed, picture quality, audio track and
/// subtitles. Changes here last for the current playback; the defaults live in
/// the full Settings page.
class QuickSettingsButton extends StatelessWidget {
  const QuickSettingsButton({super.key, required this.controller});
  final NslPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?controller.sleep]),
      builder: (context, _) {
        final p = context.pal;
        // Lit when something differs from the plain defaults.
        final changed =
            controller.speed != 1.0 ||
            !controller.subtitlesOff ||
            (controller.sleep?.active ?? false);
        return PopupMenuButton<void>(
          tooltip: 'Quick settings',
          icon: Icon(Icons.tune, color: changed ? p.accentInk : p.icon),
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
          itemBuilder: (_) => [
            PopupMenuItem<void>(
              // Not a menu choice: the panel handles its own taps.
              enabled: false,
              padding: EdgeInsets.zero,
              child: QuickSettingsPanel(controller: controller),
            ),
          ],
        );
      },
    );
  }
}

class QuickSettingsPanel extends StatelessWidget {
  const QuickSettingsPanel({super.key, required this.controller});
  final NslPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?controller.sleep]),
      builder: (context, _) {
        final p = context.pal;
        final c = controller;
        final audio = c.audioTracks;
        final subs = c.subtitleTracks;
        final eff = c.effectiveQuality;

        Widget section(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: p.textDim,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
            ],
          ),
        );

        Widget chip(String label, bool selected, VoidCallback onTap) =>
            ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12.5)),
              selected: selected,
              onSelected: (_) => onTap(),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
            );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Speed', [
              for (final s in NslPlayerController.speeds)
                chip('$s×', c.speed == s, () => c.setSpeed(s)),
            ]),
            if (c.showVideo)
              section('Video quality', [
                for (final h in c.qualityOptions)
                  chip(
                    h == 0
                        ? 'Original'
                        : h == NslPlayerController.qualityAuto
                        ? 'Auto${c.quality == h && eff != 0 ? ' · ${eff}p' : ''}'
                        : '${h}p',
                    c.quality == NslPlayerController.qualityAuto
                        ? h == NslPlayerController.qualityAuto
                        : h == eff,
                    () => c.setQuality(h),
                  ),
              ]),
            if (c.current != null && audio.length > 1)
              section('Audio track', [
                for (final t in audio)
                  chip(
                    NslPlayerController.trackLabel(t.id, t.title, t.language),
                    t.id == c.currentAudioTrack.id,
                    () => c.setAudioTrack(t),
                  ),
              ]),
            if (c.current != null)
              section('Subtitles', [
                chip('Off', c.subtitlesOff, c.disableSubtitles),
                for (final t in subs)
                  chip(
                    NslPlayerController.trackLabel(t.id, t.title, t.language),
                    t.id == c.currentSubtitleTrack.id,
                    () => c.setSubtitleTrack(t),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.folder_open, size: 16),
                  label: const Text(
                    'Load file…',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => pickSubtitleFile(c),
                ),
              ]),
            if (c.sleep != null)
              _SleepSection(timer: c.sleep!, section: section, chip: chip),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

class _SleepSection extends StatelessWidget {
  const _SleepSection({
    required this.timer,
    required this.section,
    required this.chip,
  });
  final SleepTimer timer;
  final Widget Function(String, List<Widget>) section;
  final Widget Function(String, bool, VoidCallback) chip;

  Future<void> _custom(BuildContext context) async {
    final ctl = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop after how many minutes?'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'minutes'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text)),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (minutes != null && minutes > 0) {
      timer.startCountdown(Duration(minutes: minutes));
    }
  }

  Future<void> _atTime(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    if (t != null) timer.startAt(t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (timer.active) {
      final r = timer.remaining;
      final d = timer.deadline;
      final text = switch (timer.mode) {
        SleepMode.endOfItem => 'Stops when this file ends',
        SleepMode.clock =>
          'Stops at ${TimeOfDay.fromDateTime(d!).format(context)} · in ${_clock(r!)}',
        _ => 'Stops in ${_clock(r!)}',
      };
      return section('Sleep timer', [
        Text(text, style: TextStyle(fontSize: 13, color: p.text)),
        ActionChip(
          avatar: const Icon(Icons.close, size: 16),
          label: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
          visualDensity: VisualDensity.compact,
          onPressed: timer.cancel,
        ),
      ]);
    }
    return section('Sleep timer', [
      for (final m in const [15, 30, 45, 60, 90])
        chip('$m min', false, () => timer.startCountdown(Duration(minutes: m))),
      chip('End of file', false, timer.startEndOfItem),
      chip('At time…', false, () => _atTime(context)),
      chip('Custom…', false, () => _custom(context)),
    ]);
  }
}
