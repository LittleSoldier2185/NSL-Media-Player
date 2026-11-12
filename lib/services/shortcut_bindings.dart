import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Everything a keyboard shortcut can do. [id] is stored in settings.
enum ShortcutAction {
  play('Play / pause', 'Playback'),
  back('Seek back', 'Playback'),
  fwd('Seek forward', 'Playback'),
  next('Next item', 'Playback'),
  prev('Previous item', 'Playback'),
  volup('Volume up', 'Sound'),
  voldown('Volume down', 'Sound'),
  mute('Mute', 'Sound'),
  fs('Fullscreen', 'Window and view'),
  exitfs('Exit fullscreen', 'Window and view'),
  audio('Audio only on / off', 'Window and view'),
  home('Home', 'Window and view'),
  sidebar('Show / hide sidebar', 'Window and view'),
  mini('Mini player', 'Window and view'),
  open('Open file', 'Files');

  const ShortcutAction(this.label, this.section);
  final String label;
  final String section;

  String get id => name;
}

/// One key plus modifiers, e.g. Ctrl + M.
class KeyCombo {
  const KeyCombo(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  /// Must not fire while the user types in a text field.
  bool get plain => !ctrl && !alt;

  SingleActivator get activator =>
      SingleActivator(key, control: ctrl, shift: shift, alt: alt);

  /// `keyId:flags` where flags is any of c / s / a.
  String encode() =>
      '${key.keyId}:${ctrl ? 'c' : ''}${shift ? 's' : ''}'
      '${alt ? 'a' : ''}';

  static KeyCombo? decode(String s) {
    final i = s.indexOf(':');
    if (i < 0) return null;
    final id = int.tryParse(s.substring(0, i));
    if (id == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    if (key == null) return null;
    final f = s.substring(i + 1);
    return KeyCombo(
      key,
      ctrl: f.contains('c'),
      shift: f.contains('s'),
      alt: f.contains('a'),
    );
  }

  /// Key names shown on the key caps, e.g. `['Ctrl', 'M']`.
  List<String> get labels => [
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    keyName(key),
  ];

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt);

  static String keyName(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.space) return 'Space';
    if (k == LogicalKeyboardKey.arrowLeft) return '←';
    if (k == LogicalKeyboardKey.arrowRight) return '→';
    if (k == LogicalKeyboardKey.arrowUp) return '↑';
    if (k == LogicalKeyboardKey.arrowDown) return '↓';
    if (k == LogicalKeyboardKey.escape) return 'Esc';
    final l = k.keyLabel;
    return l.isEmpty ? k.debugName ?? 'Key ${k.keyId}' : l.toUpperCase();
  }

  /// Modifier keys on their own cannot be a shortcut.
  static bool isModifier(LogicalKeyboardKey k) => {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
    LogicalKeyboardKey.fn,
  }.contains(k);
}

/// The key bindings: built-in defaults plus the user's changes. Only the
/// changes are stored (as JSON), so new defaults still reach people who never
/// touched a shortcut.
class ShortcutBindings {
  ShortcutBindings([Map<ShortcutAction, List<KeyCombo>> overrides = const {}])
    : _overrides = Map.of(overrides);

  final Map<ShortcutAction, List<KeyCombo>> _overrides;

  static final defaults = <ShortcutAction, List<KeyCombo>>{
    ShortcutAction.play: [
      KeyCombo(LogicalKeyboardKey.space),
      KeyCombo(LogicalKeyboardKey.keyK),
    ],
    ShortcutAction.back: [KeyCombo(LogicalKeyboardKey.arrowLeft)],
    ShortcutAction.fwd: [KeyCombo(LogicalKeyboardKey.arrowRight)],
    ShortcutAction.next: [KeyCombo(LogicalKeyboardKey.keyN)],
    ShortcutAction.prev: [KeyCombo(LogicalKeyboardKey.keyP)],
    ShortcutAction.volup: [KeyCombo(LogicalKeyboardKey.arrowUp)],
    ShortcutAction.voldown: [KeyCombo(LogicalKeyboardKey.arrowDown)],
    ShortcutAction.mute: [KeyCombo(LogicalKeyboardKey.keyM)],
    ShortcutAction.fs: [
      KeyCombo(LogicalKeyboardKey.keyF),
      KeyCombo(LogicalKeyboardKey.f11),
    ],
    ShortcutAction.exitfs: [KeyCombo(LogicalKeyboardKey.escape)],
    ShortcutAction.audio: [KeyCombo(LogicalKeyboardKey.keyA)],
    ShortcutAction.home: [KeyCombo(LogicalKeyboardKey.keyH)],
    ShortcutAction.sidebar: [KeyCombo(LogicalKeyboardKey.keyB, ctrl: true)],
    ShortcutAction.mini: [KeyCombo(LogicalKeyboardKey.keyM, ctrl: true)],
    ShortcutAction.open: [KeyCombo(LogicalKeyboardKey.keyO, ctrl: true)],
  };

  List<KeyCombo> combosFor(ShortcutAction a) =>
      List.unmodifiable(_overrides[a] ?? defaults[a]!);

  bool isCustom(ShortcutAction a) => _overrides.containsKey(a);
  bool get hasCustom => _overrides.isNotEmpty;

  /// Which action already uses [combo] (other than [except]), if any.
  ShortcutAction? conflict(KeyCombo combo, {ShortcutAction? except}) {
    for (final a in ShortcutAction.values) {
      if (a != except && combosFor(a).contains(combo)) return a;
    }
    return null;
  }

  ShortcutBindings withCombos(ShortcutAction a, List<KeyCombo> combos) {
    final next = Map.of(_overrides);
    if (_sameCombos(combos, defaults[a]!)) {
      next.remove(a);
    } else {
      next[a] = List.of(combos);
    }
    return ShortcutBindings(next);
  }

  ShortcutBindings withoutCustom(ShortcutAction a) {
    final next = Map.of(_overrides)..remove(a);
    return ShortcutBindings(next);
  }

  static bool _sameCombos(List<KeyCombo> a, List<KeyCombo> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// Every (action, key) pair in use.
  List<(ShortcutAction, KeyCombo)> allCombos() => [
    for (final a in ShortcutAction.values)
      for (final c in combosFor(a)) (a, c),
  ];

  String? toJson() => _overrides.isEmpty
      ? null
      : jsonEncode({
          for (final e in _overrides.entries)
            e.key.id: [for (final c in e.value) c.encode()],
        });

  /// Unknown actions / keys in [json] are ignored (older or newer versions).
  static ShortcutBindings fromJson(String? json) {
    if (json == null || json.isEmpty) return ShortcutBindings();
    try {
      final m = jsonDecode(json);
      if (m is! Map) return ShortcutBindings();
      final out = <ShortcutAction, List<KeyCombo>>{};
      for (final a in ShortcutAction.values) {
        final v = m[a.id];
        if (v is! List) continue;
        out[a] = [
          for (final s in v)
            if (s is String) ?KeyCombo.decode(s),
        ];
      }
      return ShortcutBindings(out);
    } on Object {
      return ShortcutBindings();
    }
  }
}
