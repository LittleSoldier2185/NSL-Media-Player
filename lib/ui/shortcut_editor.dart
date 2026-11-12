import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings_service.dart';
import '../services/shortcut_bindings.dart';
import 'theme.dart';

/// A key drawn like a keyboard key (raised, with a lower edge).
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: p.border),
        boxShadow: [BoxShadow(color: p.border, offset: const Offset(0, 2))],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
      ),
    );
  }
}

/// A key combo as key caps joined with "+".
class ComboCaps extends StatelessWidget {
  const ComboCaps(this.combo, {super.key});
  final KeyCombo combo;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final labels = combo.labels;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '+',
                style: TextStyle(fontSize: 12, color: p.textDim),
              ),
            ),
          KeyCap(labels[i]),
        ],
      ],
    );
  }
}

/// Edit the keys of one action: remove a key, add a new one (by pressing it)
/// or go back to the default.
Future<void> showShortcutEditor(
  BuildContext context,
  AppSettings settings,
  ShortcutAction action,
) => showDialog<void>(
  context: context,
  builder: (_) => _EditorDialog(settings: settings, action: action),
);

class _EditorDialog extends StatefulWidget {
  const _EditorDialog({required this.settings, required this.action});
  final AppSettings settings;
  final ShortcutAction action;

  @override
  State<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends State<_EditorDialog> {
  late ShortcutBindings _b = widget.settings.shortcuts;
  KeyCombo? _pending;
  ShortcutAction? _pendingConflict;
  bool _capturing = false;
  final _focus = FocusNode();

  ShortcutAction get _a => widget.action;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _commit(ShortcutBindings b) {
    widget.settings.setShortcuts(b);
    setState(() {
      _b = b;
      _pending = null;
      _pendingConflict = null;
      _capturing = false;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_capturing || e is! KeyDownEvent) return KeyEventResult.ignored;
    if (KeyCombo.isModifier(e.logicalKey)) return KeyEventResult.handled;
    final kb = HardwareKeyboard.instance;
    final combo = KeyCombo(
      e.logicalKey,
      ctrl: kb.isControlPressed,
      shift: kb.isShiftPressed,
      alt: kb.isAltPressed,
    );
    final clash = _b.conflict(combo, except: _a);
    if (clash == null) {
      if (!_b.combosFor(_a).contains(combo)) {
        _commit(_b.withCombos(_a, [..._b.combosFor(_a), combo]));
      } else {
        setState(() => _capturing = false);
      }
    } else {
      setState(() {
        _pending = combo;
        _pendingConflict = clash;
        _capturing = false;
      });
    }
    return KeyEventResult.handled;
  }

  /// Takes the key away from the other action and gives it to this one.
  void _replace() {
    final combo = _pending!;
    final other = _pendingConflict!;
    var b = _b.withCombos(other, [
      for (final c in _b.combosFor(other))
        if (c != combo) c,
    ]);
    b = b.withCombos(_a, [...b.combosFor(_a), combo]);
    _commit(b);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final combos = _b.combosFor(_a);
    return AlertDialog(
      title: Text(_a.label),
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (combos.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No key set — this action can only be used with the mouse.',
                    style: TextStyle(color: p.textDim),
                  ),
                ),
              for (final c in combos)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      ComboCaps(c),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Remove this key',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _commit(
                          _b.withCombos(_a, [
                            for (final x in combos)
                              if (x != c) x,
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (_capturing)
                Text(
                  'Press the key (or Ctrl / Alt / Shift + key) now…',
                  style: TextStyle(color: p.accentInk),
                )
              else if (_pending != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ComboCaps(_pending!),
                    Text(
                      'is already used for "${_pendingConflict!.label}".',
                      style: TextStyle(color: p.text),
                    ),
                    FilledButton(
                      onPressed: _replace,
                      child: const Text('Use it here instead'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _pending = null;
                        _pendingConflict = null;
                      }),
                      child: const Text('Keep as it was'),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: () => setState(() => _capturing = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a key'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _b.isCustom(_a)
              ? () => _commit(_b.withoutCustom(_a))
              : null,
          child: const Text('Reset to default'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
