import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
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
      listenable: controller,
      builder: (context, _) {
        final p = context.pal;
        // Lit when something differs from the plain defaults.
        final changed = controller.speed != 1.0 || !controller.subtitlesOff;
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
      listenable: controller,
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
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}
