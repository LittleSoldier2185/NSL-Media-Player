import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/shortcut_bindings.dart';

void main() {
  test('every action has a default and defaults do not clash', () {
    final b = ShortcutBindings();
    final seen = <KeyCombo>{};
    for (final a in ShortcutAction.values) {
      expect(ShortcutBindings.defaults[a], isNotNull, reason: a.id);
      for (final c in b.combosFor(a)) {
        expect(seen.add(c), isTrue, reason: '${a.id} reuses ${c.labels}');
      }
    }
  });

  test('combos round-trip through JSON and keep the rest default', () {
    final b = ShortcutBindings().withCombos(ShortcutAction.mute, [
      const KeyCombo(LogicalKeyboardKey.keyX, ctrl: true, shift: true),
    ]);
    final back = ShortcutBindings.fromJson(b.toJson());
    expect(back.combosFor(ShortcutAction.mute), [
      const KeyCombo(LogicalKeyboardKey.keyX, ctrl: true, shift: true),
    ]);
    expect(
      back.combosFor(ShortcutAction.play),
      ShortcutBindings.defaults[ShortcutAction.play],
    );
  });

  test('going back to the defaults stores nothing', () {
    final b = ShortcutBindings().withCombos(ShortcutAction.next, [
      const KeyCombo(LogicalKeyboardKey.keyX),
    ]);
    expect(b.hasCustom, isTrue);
    final reset = b.withCombos(
      ShortcutAction.next,
      ShortcutBindings.defaults[ShortcutAction.next]!,
    );
    expect(reset.hasCustom, isFalse);
    expect(reset.toJson(), isNull);
  });

  test('conflict finds the other action, not the one being edited', () {
    final b = ShortcutBindings();
    const m = KeyCombo(LogicalKeyboardKey.keyM);
    expect(b.conflict(m), ShortcutAction.mute);
    expect(b.conflict(m, except: ShortcutAction.mute), isNull);
    // Ctrl+M (mini player) is a different key from M (mute).
    expect(
      b.conflict(const KeyCombo(LogicalKeyboardKey.keyM, ctrl: true)),
      ShortcutAction.mini,
    );
  });

  test('plain means no Ctrl or Alt; bad stored data is ignored', () {
    expect(const KeyCombo(LogicalKeyboardKey.keyA).plain, isTrue);
    expect(const KeyCombo(LogicalKeyboardKey.keyA, shift: true).plain, isTrue);
    expect(const KeyCombo(LogicalKeyboardKey.keyA, ctrl: true).plain, isFalse);
    expect(ShortcutBindings.fromJson('not json').hasCustom, isFalse);
    expect(
      ShortcutBindings.fromJson('{"mute":["zzz","1:"],"nope":[]}')
          .combosFor(ShortcutAction.mute),
      isEmpty,
    );
  });
}
