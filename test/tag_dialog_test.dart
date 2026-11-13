import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/ui/tag_dialog.dart';
import 'package:nsl_media_player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tag_test_support.dart';

void main() {
  late Directory tmp;
  late LibraryService lib;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nsl_tagdlg');
    SharedPreferences.setMockInitialValues({});
    lib = LibraryService(
      await SharedPreferences.getInstance(),
      indexFile: File('${tmp.path}/index.json'),
      autoRescan: false,
    );
  });
  tearDown(() => tmp.delete(recursive: true));

  /// Waits (real time) until the box has finished saving and closed.
  Future<void> closed(WidgetTester t) async {
    for (
      var i = 0;
      i < 100 && find.byType(TagDialog).evaluate().isNotEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, List<String> paths) async {
    t.view.physicalSize = const Size(1000, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, const Color(0xFF7C5CFF)),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showTagEditor(context, paths: paths, library: lib),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump();
    // The tags are read in another isolate.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await t.pump();
  }

  testWidgets('shows the tags, saves a change into the file and the library', (
    t,
  ) async {
    final f = makeMp3(tmp, 'a.mp3');
    await t.runAsync(() => lib.addFolder(tmp.path));
    await open(t, [f.path]);

    expect(find.text('Edit info'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old artist'), findsOneWidget);

    await t.enterText(find.widgetWithText(TextField, 'Old title'), 'Fresh');
    await t.enterText(
      find.widgetWithText(TextField, 'Old album'),
      'Fresh album',
    );
    await t.tap(find.text('Save'));
    await closed(t);

    final m = readMetadata(f, getImage: false);
    expect(m.title, 'Fresh');
    expect(m.album, 'Fresh album');
    expect(m.artist, 'Old artist');
    final row = lib.items.singleWhere((i) => i.path == f.path);
    expect(row.title, 'Fresh');
    expect(row.album, 'Fresh album');
    expect(find.text('Edit info'), findsNothing, reason: 'closed after saving');
  });

  testWidgets('several songs: no title box, only filled fields change', (
    t,
  ) async {
    final a = makeMp3(tmp, 'a.mp3', title: 'One');
    final b = makeMp3(tmp, 'b.mp3', title: 'Two');
    await t.runAsync(() => lib.addFolder(tmp.path));
    await open(t, [a.path, b.path]);

    expect(find.text('Edit info (2 songs)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Old album'), 'Shared');
    await t.tap(find.text('Save'));
    await closed(t);

    for (final (f, title) in [(a, 'One'), (b, 'Two')]) {
      final m = readMetadata(f, getImage: false);
      expect(m.title, title);
      expect(m.album, 'Shared');
      expect(m.artist, 'Old artist');
    }
  });

  testWidgets('a file that cannot be edited is skipped', (t) async {
    final f = File('${tmp.path}/a.ogg')..writeAsBytesSync([1, 2, 3]);
    await open(t, [f.path]);
    expect(find.text('These files cannot be edited.'), findsOneWidget);
  });
}
