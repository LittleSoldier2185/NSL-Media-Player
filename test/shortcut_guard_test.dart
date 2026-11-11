import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/ui/shortcut_guard.dart';

class _Hit extends Intent {
  const _Hit(this.name, {this.plain = true});
  final String name;
  final bool plain;
}

void main() {
  late List<String> hits;
  final field = GlobalKey();
  final focus = FocusNode();
  final pageFocus = FocusNode();

  Widget app() => MaterialApp(
    home: Scaffold(
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyH): _Hit('home'),
          SingleActivator(LogicalKeyboardKey.space): _Hit('play'),
          SingleActivator(LogicalKeyboardKey.keyB, control: true): _Hit(
            'sidebar',
            plain: false,
          ),
        },
        child: Actions(
          actions: {
            _Hit: GuardedAction<_Hit>(
              onInvoke: (i) => hits.add(i.name),
              isPlainKey: (i) => i.plain,
            ),
          },
          child: Focus(
            focusNode: pageFocus,
            autofocus: true,
            child: Column(
              children: [
                TextField(key: field, focusNode: focus),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  setUp(() => hits = []);

  testWidgets('plain keys run the shortcut when nothing is being typed', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(hits, ['home', 'play']);
  });

  testWidgets('plain keys are left to the text field while typing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(field));
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(hits, isEmpty);
  });

  testWidgets('Ctrl shortcuts still work while typing', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(field));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(hits, ['sidebar']);
  });

  testWidgets('plain keys work again after the field loses focus', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(field));
    await tester.pump();
    // Unfocusing sends focus to the route's scope; the app then gives it back
    // to the page (see _restoreFocus in PlayerPage).
    focus.unfocus();
    pageFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    expect(hits, ['home']);
  });
}
