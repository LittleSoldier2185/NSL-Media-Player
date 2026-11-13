import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/book_service.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/thumbnail_service.dart';
import 'package:nsl_media_player/ui/books_view.dart';
import 'package:nsl_media_player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nsl_books_test');
  });
  tearDown(() => tmp.delete(recursive: true));

  group('BookService', () {
    BookService make() => BookService(file: File('${tmp.path}\\books.json'));

    test('remembers the page and the length', () {
      final b = make();
      expect(b.stateOf('C:\\a\\x.pdf'), isNull);
      b.opened('C:\\a\\x.pdf', pageCount: 200);
      b.savePage('C:\\a\\x.pdf', 51);
      final s = b.stateOf('c:\\A\\X.PDF')!; // paths compare without case
      expect(s.page, 51);
      expect(s.pageCount, 200);
      expect(s.progress, closeTo(0.25, 0.01));
      expect(s.started, isTrue);
      expect(s.finished, isFalse);
      b.dispose();
    });

    test('a page outside the book is clamped', () {
      final b = make();
      b.opened('x.pdf', pageCount: 10);
      b.savePage('x.pdf', 99);
      expect(b.stateOf('x.pdf')!.page, 10);
      expect(b.stateOf('x.pdf')!.finished, isTrue);
      b.savePage('x.pdf', -4);
      expect(b.stateOf('x.pdf')!.page, 1);
      b.dispose();
    });

    test('in progress = started and not finished, latest first', () async {
      final b = make();
      b.opened('a.pdf', pageCount: 10);
      b.savePage('a.pdf', 3);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      b.opened('b.pdf', pageCount: 10);
      b.savePage('b.pdf', 4);
      b.opened('c.pdf', pageCount: 10);
      b.savePage('c.pdf', 10); // finished
      b.opened('d.pdf', pageCount: 10); // opened, still on page 1
      expect(b.inProgress.map((s) => s.path), ['b.pdf', 'a.pdf']);
      b.dispose();
    });

    test('bookmarks: toggle, sort by page, rename, no duplicates', () {
      final b = make();
      expect(b.toggleBookmark('x.pdf', 9), isTrue);
      b.addBookmark('x.pdf', 2, label: '  Intro ');
      b.addBookmark('x.pdf', 9); // already marked
      expect(b.bookmarksOf('x.pdf').map((m) => m.page), [2, 9]);
      expect(b.bookmarksOf('x.pdf').first.label, 'Intro');
      b.renameBookmark('x.pdf', 9, 'Key part');
      expect(b.bookmarksOf('x.pdf').last.label, 'Key part');
      expect(b.toggleBookmark('x.pdf', 9), isFalse);
      expect(b.hasBookmark('x.pdf', 9), isFalse);
      b.dispose();
    });

    test('everything survives a restart', () async {
      final b = make();
      b.opened('x.pdf', pageCount: 30);
      b.savePage('x.pdf', 12);
      b.addBookmark('x.pdf', 5, label: 'Chapter');
      await b.save();
      b.dispose();
      final again = make();
      expect(again.stateOf('x.pdf')!.page, 12);
      expect(again.stateOf('x.pdf')!.pageCount, 30);
      expect(again.bookmarksOf('x.pdf').single.label, 'Chapter');
      again.dispose();
    });

    test('a damaged file is ignored', () {
      File('${tmp.path}\\books.json').writeAsStringSync('{not json');
      final b = make();
      expect(b.recent, isEmpty);
      b.dispose();
    });

    test('markUnread forgets the place but keeps the bookmarks', () {
      final b = make();
      b.opened('x.pdf', pageCount: 10);
      b.savePage('x.pdf', 6);
      b.addBookmark('x.pdf', 3);
      b.markUnread('x.pdf');
      expect(b.stateOf('x.pdf')!.started, isFalse);
      expect(b.bookmarksOf('x.pdf'), hasLength(1));
      b.dispose();
    });
  });

  group('Books shelf', () {
    Future<(LibraryService, BookService)> setup(List<String> names) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lib = LibraryService(
        prefs,
        indexFile: File('${tmp.path}\\index.json'),
        autoRescan: false,
        thumbnails: ThumbnailService(
          dir: Directory('${tmp.path}\\thumbs'),
          pdfCover: (_) async => null,
        ),
      );
      lib.setItemsForTest([
        for (final n in names)
          LibraryItem(path: 'C:\\books\\$n.pdf', title: n, modified: 1),
      ]);
      final books = BookService(file: File('${tmp.path}\\books.json'));
      return (lib, books);
    }

    Widget host(LibraryService lib, BookService books) => MaterialApp(
      theme: buildTheme(Brightness.dark, const Color(0xFFF4B860)),
      home: Scaffold(
        body: BooksView(library: lib, books: books, onOpenLibrary: () {}),
      ),
    );

    testWidgets('lists the books and filters them by progress', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (lib, books) = await setup(['Atlas', 'Birds', 'Cooking']);
      books.opened('C:\\books\\Birds.pdf', pageCount: 100);
      books.savePage('C:\\books\\Birds.pdf', 40);
      books.opened('C:\\books\\Cooking.pdf', pageCount: 50);
      books.savePage('C:\\books\\Cooking.pdf', 50);

      await t.pumpWidget(host(lib, books));
      await t.pump();
      expect(find.text('Atlas'), findsOneWidget);
      expect(find.text('Not started'), findsWidgets);
      // The unfinished book is offered under "Continue reading".
      expect(find.text('CONTINUE READING'), findsOneWidget);

      await t.tap(find.text('Finished').first);
      await t.pump();
      expect(find.text('Cooking'), findsOneWidget);
      expect(find.text('Atlas'), findsNothing);
      expect(find.text('CONTINUE READING'), findsNothing);

      await t.tap(find.text('Reading').first);
      await t.pump();
      expect(find.text('Birds'), findsWidgets);
      expect(find.text('Cooking'), findsNothing);

      // Stop the debounced save before the test ends.
      await t.pumpWidget(const SizedBox());
      books.dispose();
    });

    testWidgets('search narrows the shelf; an empty library explains', (
      t,
    ) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (lib, books) = await setup(['Atlas', 'Birds']);
      await t.pumpWidget(host(lib, books));
      await t.pump();
      await t.enterText(find.byType(TextField), 'bir');
      await t.pump();
      expect(find.text('Birds'), findsOneWidget);
      expect(find.text('Atlas'), findsNothing);
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pump();
      expect(find.text('No books match.'), findsOneWidget);

      final (empty, b2) = await setup([]);
      await t.pumpWidget(host(empty, b2));
      await t.pump();
      expect(find.textContaining('Add a folder'), findsOneWidget);
    });
  });
}
