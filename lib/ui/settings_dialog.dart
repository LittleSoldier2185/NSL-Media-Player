import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'theme.dart';

Future<void> showSettings(BuildContext context, AppSettings settings) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: context.pal.panelTop,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: context.pal.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListenableBuilder(
          listenable: settings,
          builder: (ctx, _) => _SettingsBody(settings: settings),
        ),
      ),
    ),
  );
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody({required this.settings});
  final AppSettings settings;

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  late final _hex = TextEditingController(text: _toHex(widget.settings.accent));

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _submitHex(String v) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
    if (m != null) {
      widget.settings.setAccent(
        Color(0xFF000000 | int.parse(m.group(1)!, radix: 16)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = widget.settings;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Close settings',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: p.icon),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row(
            p,
            'Theme',
            'Dark or Light. System follows your Windows setting.',
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.setThemeMode(v.first),
            ),
          ),
          const SizedBox(height: 20),
          _row(
            p,
            'Accent color',
            'Pick a preset, or type any hex color.',
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (name, c) in accentPresets)
                  Semantics(
                    label: '$name accent',
                    button: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        s.setAccent(c);
                        _hex.text = _toHex(c);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: s.accent.toARGB32() == c.toARGB32()
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
                    onSubmitted: _submitHex,
                    onChanged: _submitHex,
                    style: TextStyle(fontSize: 13, color: p.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _row(
            p,
            'Audio-only when minimized',
            'Stop decoding video while the window is minimized to save CPU/GPU.',
            Switch(value: s.autoAudioOnly, onChanged: s.setAutoAudioOnly),
          ),
        ],
      ),
    );
  }

  Widget _row(NslPalette p, String title, String desc, Widget control) {
    return Column(
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
        const SizedBox(height: 2),
        Text(desc, style: TextStyle(fontSize: 12, color: p.textDim)),
        const SizedBox(height: 10),
        control,
      ],
    );
  }
}
