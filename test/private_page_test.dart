import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/book_service.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/playlist_service.dart';
import 'package:nsl_media_player/services/private_hub.dart';
import 'package:nsl_media_player/services/private_service.dart';
import 'package:nsl_media_player/ui/private_page.dart';
import 'package:nsl_media_player/ui/sidebar.dart';
import 'package:nsl_media_player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late PrivateHub hub;
  late PrivateService lock;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nsl_private_page');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    lock = PrivateService(
      file: File('${tmp.path}\private.json'),
      iterations: 10,
      idleTimer: false,
    );
    LibraryService lib(String name) => LibraryService(
      prefs,
      indexFile: File('${tmp.path}\$name.json'),
      autoRescan: false,
    );
    hub = PrivateHub.forTest(
      lock: lock,
      library: lib('p'),
      normal: lib('n'),
      playlists: PlaylistService(file: File('${tmp.path}\pl.json')),
      albums: PlaylistService(file: File('${tmp.path}\al.json')),
      books: BookService(file: File('${tmp.path}\bk.json')),
    );
  });
  tearDown(() async {
    lock.dispose();
    await tmp.delete(recursive: true);
  });

  Widget app(Widget child) => MaterialApp(
    theme: buildTheme(Brightness.dark, const Color(0xFF7C5CFF)),
    home: Scaffold(body: child),
  );

  testWidgets('first visit asks for a PIN, then opens', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(PrivatePage(hub: hub, controller: null, onOpenPlayer: () {})),
    );
    expect(find.text('Set up Private'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.enterText(find.byType(TextField).last, '9999');
    await tester.tap(find.text('Set PIN and open'));
    await tester.pump();
    expect(find.text('The two PINs are not the same.'), findsOneWidget);
    expect(lock.hasPin, isFalse);

    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Set PIN and open'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(lock.unlocked, isTrue);
    expect(find.text('Lock now'), findsWidgets);
  });

  testWidgets(
    'locked: wrong PIN is refused, right PIN opens, Lock now closes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => lock.setPin('1234'));
      lock.lock();
      await tester.pumpWidget(
        app(PrivatePage(hub: hub, controller: null, onOpenPlayer: () {})),
      );
      expect(find.text('Private is locked'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text('Unlock'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Wrong PIN.'), findsOneWidget);
      expect(lock.unlocked, isFalse);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Unlock'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(lock.unlocked, isTrue);
      expect(find.text('Private is locked'), findsNothing);

      await tester.tap(find.text('Lock now').first);
      await tester.pump();
      expect(find.text('Private is locked'), findsOneWidget);
    },
  );

  testWidgets('the sidebar shows Private only when asked', (tester) async {
    Widget bar(bool show) => app(
      Row(
        children: [
          AppSidebar(
            mode: SidebarMode.open,
            current: NavDest.home,
            onSelect: (_) {},
            onToggleWide: () {},
            showPrivate: show,
          ),
        ],
      ),
    );
    await tester.pumpWidget(bar(false));
    expect(find.text('Private'), findsNothing);
    await tester.pumpWidget(bar(true));
    expect(find.text('Private'), findsOneWidget);
  });
}
