import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/history_service.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/settings_service.dart';
import '../services/shortcut_bindings.dart';
import 'shortcut_editor.dart';
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
  library(
    'Library',
    Icons.folder_outlined,
    'Your media folders and what the player remembers.',
  ),
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
    required this.library,
    required this.onClose,
  });

  final AppSettings settings;
  final NslPlayerController controller;
  final HistoryService history;
  final LibraryService library;
  final VoidCallback onClose;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _Cat _cat = _Cat.general;

  /// Size of the thumbnail cache; re-read after clearing.
  late Future<int> _thumbSize = widget.library.thumbnails.cacheSizeBytes();
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
      listenable: Listenable.merge([s, c, widget.library]),
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
            _toggle(
              p,
              'Windows media controls',
              'Media keys and the Windows volume panel show the current title and control playback.',
              s.smtcEnabled,
              (v) => s.put('smtcEnabled', v),
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
              'Open in its own window',
              'Keep the main window open while the mini player plays; pick '
                  'things there and they play in the mini player. Turn off to '
                  'shrink the main window into the mini player instead.',
              s.miniSeparateWindow,
              (v) => s.put('miniSeparateWindow', v),
            ),
            _row(
              p,
              'Window size',
              'Drag the edges of the mini player to resize it; the size is '
                  'remembered. A video keeps its shape.',
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: s.resetMiniSize,
                child: const Text('Reset size'),
              ),
            ),
            _toggle(
              p,
              'Show video',
              'Show the picture of videos in the mini player. Turn off to play '
                  'sound only, which uses less CPU and GPU.',
              s.miniShowVideo,
              (v) => s.put('miniShowVideo', v),
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
        final lib = widget.library;
        return [
          _group(p, [
            _row(
              p,
              'Media folders',
              lib.folders.isEmpty
                  ? 'Save the folders where you keep your music and videos. '
                        'You can add as many as you like.'
                  : '${lib.folders.length} saved · ${lib.items.length} files',
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () async {
                      final dir = await FilePicker.platform.getDirectoryPath();
                      if (dir == null) return;
                      final added = await lib.addFolder(dir);
                      if (!added && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('That folder is already saved.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add folder'),
                  ),
                  if (lib.folders.isNotEmpty)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: lib.scanning ? null : lib.scan,
                      child: Text(lib.scanning ? 'Scanning…' : 'Rescan all'),
                    ),
                ],
              ),
            ),
            for (final f in lib.folders)
              _row(
                p,
                LibraryService.folderName(f),
                '$f · ${lib.countIn(f)} files',
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => lib.removeFolder(f),
                  child: const Text('Remove'),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _group(p, [
            FutureBuilder<int>(
              future: _thumbSize,
              builder: (context, snap) {
                final bytes = snap.data;
                return _row(
                  p,
                  'Thumbnails',
                  'Cover art and video frames shown in the Library are saved '
                      'so they load fast. '
                      '${bytes == null ? '' : 'Using ${(bytes / 1048576).toStringAsFixed(1)} MB. '}'
                      'Clear them if a picture looks wrong; they are rebuilt '
                      'as you browse.',
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () async {
                      await widget.library.thumbnails.clearCache();
                      if (!mounted) return;
                      setState(
                        () => _thumbSize = widget.library.thumbnails
                            .cacheSizeBytes(),
                      );
                    },
                    child: const Text('Clear thumbnails'),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 16),
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
        return [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final section in const [
                  'Playback',
                  'Sound',
                  'Window and view',
                  'Files',
                ]) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
                    child: Text(
                      section.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: p.textDim,
                      ),
                    ),
                  ),
                  _group(p, [
                    for (final a in ShortcutAction.values)
                      if (a.section == section) _shortcutRow(p, a, s, c),
                  ]),
                  const SizedBox(height: 22),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: s.shortcuts.hasCustom
                        ? () => s.setShortcuts(ShortcutBindings())
                        : null,
                    child: const Text('Reset all to defaults'),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'These work in the main window and in the mini player.',
                    style: TextStyle(fontSize: 12.5, color: p.textDim),
                  ),
                ),
              ],
            ),
          ),
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

  // ---- Shortcuts ----

  Widget _shortcutRow(
    NslPalette p,
    ShortcutAction a,
    AppSettings s,
    NslPlayerController c,
  ) {
    final combos = s.shortcuts.combosFor(a);
    final hint = switch (a) {
      ShortcutAction.back || ShortcutAction.fwd => '${s.seekStep} seconds',
      ShortcutAction.volup || ShortcutAction.voldown => '5%',
      ShortcutAction.audio => 'Stops decoding the picture to save CPU and GPU',
      _ => null,
    };
    final alts = <Widget>[];
    for (var i = 0; i < combos.length; i++) {
      if (i > 0) {
        alts.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('or', style: TextStyle(fontSize: 12, color: p.textDim)),
          ),
        );
      }
      alts.add(ComboCaps(combos[i]));
    }
    if (combos.isEmpty) {
      alts.add(
        Text('Not set', style: TextStyle(fontSize: 12.5, color: p.textDim)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hint,
                      style: TextStyle(fontSize: 12, color: p.textDim),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(mainAxisSize: MainAxisSize.min, children: alts),
          IconButton(
            tooltip: 'Change keys',
            icon: Icon(
              s.shortcuts.isCustom(a) ? Icons.edit : Icons.edit_outlined,
              size: 18,
              color: s.shortcuts.isCustom(a) ? p.accentInk : p.icon,
            ),
            onPressed: () => showShortcutEditor(context, s, a),
          ),
        ],
      ),
    );
  }

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
        // Full-width rows: otherwise each row shrinks to its content and sits
        // in the middle with a divider of its own length.
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
