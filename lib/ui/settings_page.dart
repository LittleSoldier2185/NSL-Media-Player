import 'dart:io';

import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/media_types.dart';
import '../services/settings_service.dart';
import 'theme.dart';

enum _Cat {
  general(
    'General',
    Icons.tune,
    'Appearance and how the app registers with Windows.',
  ),
  playback(
    'Playback',
    Icons.play_arrow_rounded,
    'How files start, continue and respond to controls.',
  ),
  video(
    'Video',
    Icons.movie_outlined,
    'Quality, decoding and audio-only behavior.',
  ),
  mini(
    'Mini player',
    Icons.picture_in_picture_alt_outlined,
    'The small always-on-top window.',
  ),
  library('Library', Icons.folder_outlined, 'What the player remembers.'),
  shortcuts(
    'Shortcuts',
    Icons.keyboard_outlined,
    'Keyboard controls that work in every mode.',
  ),
  about('About', Icons.info_outline, 'Version and playback engine.');

  const _Cat(this.label, this.icon, this.desc);
  final String label;
  final IconData icon;
  final String desc;
}

/// Full Settings page, following the "Settings" board of the UI design.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.controller,
    required this.history,
    required this.onClose,
  });

  final AppSettings settings;
  final NslPlayerController controller;
  final HistoryService history;
  final VoidCallback onClose;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Cat _cat = _Cat.general;
  late final _hex = TextEditingController(text: _toHex(widget.settings.accent));

  AppSettings get s => widget.settings;
  NslPlayerController get c => widget.controller;

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setAccent(Color c) {
    s.setAccent(c);
    _hex.text = _toHex(c);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: Listenable.merge([s, c]),
      builder: (context, _) => Row(
        children: [
          _nav(p),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
              children: [
                Text(
                  _cat.label,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _cat.desc,
                  style: TextStyle(fontSize: 14, color: p.textDim),
                ),
                const SizedBox(height: 20),
                ..._body(context, p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(NslPalette p) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.titleBar,
        border: Border(right: BorderSide(color: p.panelBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 20, color: p.icon),
                  const SizedBox(width: 12),
                  Text('Back', style: TextStyle(fontSize: 14, color: p.icon)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final k in _Cat.values)
            Semantics(
              selected: k == _cat,
              button: true,
              child: InkWell(
                onTap: () => setState(() => _cat = k),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: k == _cat ? p.hover : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        k.icon,
                        size: 20,
                        color: k == _cat ? p.accentInk : p.icon,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        k.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: k == _cat ? p.text : p.icon,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, NslPalette p) {
    switch (_cat) {
      case _Cat.general:
        return [
          _defaultPlayerCard(p),
          const SizedBox(height: 20),
          _group(p, [
            _seg<ThemeMode>(
              p,
              'Theme',
              'Dark or Light. System follows your Windows setting.',
              {
                ThemeMode.dark: 'Dark',
                ThemeMode.light: 'Light',
                ThemeMode.system: 'System',
              },
              s.themeMode,
              s.setThemeMode,
            ),
            _row(
              p,
              'Accent color',
              'Pick a preset, or type any hex color.',
              _accentControl(p),
            ),
            _toggle(
              p,
              'Remember window size and position',
              'Open the player where you left it.',
              s.rememberWindow,
              (v) => s.put('rememberWindow', v),
            ),
          ]),
        ];
      case _Cat.playback:
        return [
          _group(p, [
            _toggle(
              p,
              'Resume where you left off',
              'Show partly played files under Continue on Home.',
              s.resume,
              (v) => s.put('resume', v),
            ),
            _toggle(
              p,
              'Play the next item automatically',
              'Move on to the next file in the queue when one ends.',
              s.autoNext,
              (v) {
                s.put('autoNext', v);
                c.setAutoNext(v);
              },
            ),
            _slider(
              p,
              'Default volume',
              'Volume used when the app starts.',
              (s.defaultVolume ?? c.player.state.volume).round(),
              0,
              100,
              '%',
              (v) => s.put('defaultVolume', v.toDouble()),
            ),
            _select<double>(
              p,
              'Default speed',
              'Playback speed for new files.',
              {for (final v in NslPlayerController.speeds) v: '$v×'},
              s.defaultSpeed,
              (v) {
                s.put('defaultSpeed', v);
                c.setSpeed(v);
              },
            ),
            _seg<int>(
              p,
              'Seek step',
              'How far the arrow keys and skip buttons jump.',
              {5: '5 s', 10: '10 s', 30: '30 s'},
              s.seekStep,
              (v) {
                s.put('seekStep', v);
                c.seekStep = v;
              },
            ),
          ]),
        ];
      case _Cat.video:
        return [
          _group(p, [
            _seg<int>(
              p,
              'Maximum quality',
              'Limits the picture size. A file is never shown larger than its own resolution. Auto drops to 480p while the window is minimized.',
              {
                0: 'Original',
                NslPlayerController.qualityAuto: 'Auto',
                for (final h in NslPlayerController.qualityHeights) h: '${h}p',
              },
              c.quality,
              c.setQuality,
            ),
            _select<String>(
              p,
              'Hardware decoding',
              'Use the graphics card to decode video. Auto picks what works.',
              {'auto': 'Auto', 'on': 'On', 'off': 'Off'},
              s.hwdec,
              (v) {
                s.put('hwdec', v);
                c.setHwdec(v);
              },
            ),
            _toggle(
              p,
              'Audio only when minimized',
              'Stop decoding video while the window is minimized to save CPU and GPU.',
              s.autoAudioOnly,
              s.setAutoAudioOnly,
            ),
            _toggle(
              p,
              'Audio only by default',
              'Play video files as audio only (no picture) until you turn the picture on with A.',
              s.audioOnlyDefault,
              (v) {
                s.put('audioOnlyDefault', v);
                c.setAudioOnly(v);
              },
            ),
          ]),
        ];
      case _Cat.mini:
        return [
          _group(p, [
            _slider(
              p,
              'Default opacity',
              'How see-through the mini player is when it opens.',
              s.miniOpacity,
              20,
              100,
              '%',
              (v) {
                s.miniOpacity = v;
                s.put('miniOpacity', s.miniOpacity);
              },
            ),
            _toggle(
              p,
              'Always on top',
              'Keep the mini player above other windows.',
              s.miniOnTop,
              (v) {
                s.miniOnTop = v;
                s.put('miniOnTop', v);
              },
            ),
            _toggle(
              p,
              'Remember position',
              'Reopen the mini player at its last place on screen.',
              s.miniRememberPos,
              (v) => s.put('miniRememberPos', v),
            ),
          ]),
        ];
      case _Cat.library:
        return [
          _group(p, [
            _toggle(
              p,
              'Keep play history',
              'Used for Continue and the weekly chart on Home.',
              s.keepHistory,
              (v) => s.put('keepHistory', v),
            ),
            _row(
              p,
              'Clear play history',
              'Removes the history only. Your files are not touched.',
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _confirmClear(context),
                child: const Text('Clear history'),
              ),
            ),
          ]),
        ];
      case _Cat.shortcuts:
        const keys = [
          ('Play / pause', ['Space', 'K']),
          ('Seek back / forward', ['←', '→']),
          ('Volume up / down', ['↑', '↓']),
          ('Mute', ['M']),
          ('Next / previous item', ['N', 'P']),
          ('Fullscreen', ['F', 'F11']),
          ('Exit fullscreen', ['Esc']),
          ('Audio only on / off', ['A']),
          ('Mini player', ['Ctrl', 'M']),
          ('Open file', ['Ctrl', 'O']),
        ];
        return [
          _group(p, [
            for (final (action, ks) in keys)
              _row(
                p,
                action,
                null,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final k in ks)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        constraints: const BoxConstraints(minWidth: 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.track,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: p.border),
                        ),
                        child: Text(
                          k,
                          style: TextStyle(fontSize: 12.5, color: p.text),
                        ),
                      ),
                  ],
                ),
              ),
          ]),
        ];
      case _Cat.about:
        return [
          _group(p, [
            _row(
              p,
              'Version',
              null,
              Text('0.1.0', style: TextStyle(color: p.text)),
            ),
            _row(
              p,
              'Playback engine',
              null,
              Text('libmpv through media_kit', style: TextStyle(color: p.text)),
            ),
            _row(
              p,
              'Built with',
              null,
              Text('Flutter, Windows desktop', style: TextStyle(color: p.text)),
            ),
          ]),
        ];
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear play history?'),
        content: const Text(
          'Continue, the weekly chart and play counts will be reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) widget.history.clear();
  }

  // ---- Default player card ----

  /// Extensions registered by the installer (installer/nsl_media_player.iss)
  /// appear under `OpenWithProgids`; without the installer this shows 0.
  int _registeredCount() {
    if (!Platform.isWindows) return 0;
    var n = 0;
    final all = [...audioExtensions, ...videoExtensions];
    for (final e in all) {
      try {
        final r = Process.runSync('reg', [
          'query',
          r'HKCU\Software\Classes\.' + e + r'\OpenWithProgids',
          '/v',
          'NslMediaPlayer.File',
        ]);
        if (r.exitCode == 0) n++;
      } on ProcessException {
        return 0;
      }
    }
    return n;
  }

  Widget _defaultPlayerCard(NslPalette p) {
    final all = [...audioExtensions, ...videoExtensions];
    return _card(
      p,
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Default player',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Windows only lets you choose the default app yourself. Pick NSL Media Player in Windows Default apps.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: p.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: () => Process.run('cmd', [
                    '/c',
                    'start',
                    '',
                    'ms-settings:defaultapps',
                  ]),
                  child: const Text('Open Windows Default apps'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in all)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.border),
                    ),
                    child: Text(
                      '.$e',
                      style: TextStyle(fontSize: 12, color: p.text),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            FutureBuilder<int>(
              future: Future(_registeredCount),
              builder: (_, snap) => Text(
                snap.hasData
                    ? 'Registered for ${snap.data} of ${all.length} file types'
                    : 'Checking file types…',
                style: TextStyle(fontSize: 12, color: p.textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Building blocks ----

  Widget _card(NslPalette p, Widget child) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: p.panelBorder),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.panelTop, p.panelBottom],
      ),
    ),
    child: child,
  );

  Widget _group(NslPalette p, List<Widget> rows) => _card(
    p,
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: p.panelBorder)),
              ),
              child: rows[i],
            ),
        ],
      ),
    ),
  );

  Widget _row(NslPalette p, String title, String? desc, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 24,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: p.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          control,
        ],
      ),
    );
  }

  Widget _toggle(
    NslPalette p,
    String title,
    String desc,
    bool v,
    ValueChanged<bool> on,
  ) => _row(p, title, desc, Switch(value: v, onChanged: on));

  Widget _seg<T>(
    NslPalette p,
    String title,
    String desc,
    Map<T, String> opts,
    T value,
    ValueChanged<T> on,
  ) => _row(
    p,
    title,
    desc,
    SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final e in opts.entries)
          ButtonSegment(value: e.key, label: Text(e.value)),
      ],
      selected: {value},
      onSelectionChanged: (v) => on(v.first),
    ),
  );

  Widget _select<T>(
    NslPalette p,
    String title,
    String desc,
    Map<T, String> opts,
    T value,
    ValueChanged<T> on,
  ) => _row(
    p,
    title,
    desc,
    DropdownMenu<T>(
      key: ValueKey('$title$value'),
      initialSelection: value,
      width: 160,
      requestFocusOnTap: false,
      dropdownMenuEntries: [
        for (final e in opts.entries)
          DropdownMenuEntry(value: e.key, label: e.value),
      ],
      onSelected: (v) {
        if (v != null) on(v);
      },
    ),
  );

  Widget _slider(
    NslPalette p,
    String title,
    String desc,
    int value,
    int min,
    int max,
    String unit,
    ValueChanged<int> on,
  ) => _row(
    p,
    title,
    desc,
    SizedBox(
      width: 240,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              label: '$value$unit',
              onChanged: (v) => on(v.round()),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value$unit',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 13, color: p.text),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _accentControl(NslPalette p) {
    void submit(String v) {
      final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
      if (m != null)
        s.setAccent(Color(0xFF000000 | int.parse(m.group(1)!, radix: 16)));
    }

    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (name, col) in accentPresets)
          Semantics(
            label: '$name accent',
            button: true,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _setAccent(col),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: col,
                  shape: BoxShape.circle,
                  border: s.accent.toARGB32() == col.toARGB32()
                      ? Border.all(color: p.text, width: 2)
                      : null,
                ),
              ),
            ),
          ),
        SizedBox(
          width: 96,
          child: TextField(
            controller: _hex,
            onSubmitted: submit,
            onChanged: submit,
            style: TextStyle(fontSize: 13, color: p.text),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
