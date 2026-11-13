import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/file_locator.dart';
import 'package:nsl_media_player/ui/file_menu.dart';

void main() {
  testWidgets('the menu lists the three commands and runs the chosen one', (
    t,
  ) async {
    final copied = <String>[];
    final locator = FileLocator(
      copyText: (s) async => copied.add(s),
      fileExists: (_) => true,
      dirExists: (_) => true,
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => PopupMenuButton<String>(
              itemBuilder: (_) => fileMenuItems(),
              onSelected: (v) {
                expect(isFileCommand(v), isTrue);
                runFileCommand(context, v, r'C:\Music\a.mp3', locator: locator);
              },
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    expect(find.text('Show in folder'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Copy file'), findsOneWidget);

    await t.tap(find.text('Copy path'));
    await t.pumpAndSettle();
    expect(copied, [r'C:\Music\a.mp3']);
    expect(find.text('Path copied.'), findsOneWidget);
  });

  test('menu values are recognised', () {
    expect(isFileCommand('file:copyPath'), isTrue);
    expect(isFileCommand('edit'), isFalse);
  });
}
