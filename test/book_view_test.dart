import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/book_service.dart';
import 'package:nsl_media_player/ui/book_layout.dart';

void main() {
  group('groupPages', () {
    test('scroll and single: one page per unit', () {
      for (final m in [BookViewMode.scroll, BookViewMode.single]) {
        expect(groupPages(3, mode: m, coverAlone: true), [
          [1],
          [2],
          [3],
        ]);
      }
    });

    test('spread with the cover alone: 1 | 2 3 | 4 5 | 6', () {
      expect(groupPages(6, mode: BookViewMode.spread, coverAlone: true), [
        [1],
        [2, 3],
        [4, 5],
        [6],
      ]);
    });

    test('spread without a lone cover: 1 2 | 3 4 | 5', () {
      expect(groupPages(5, mode: BookViewMode.spread, coverAlone: false), [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('an empty or one-page book', () {
      expect(
        groupPages(0, mode: BookViewMode.spread, coverAlone: true),
        isEmpty,
      );
      expect(groupPages(1, mode: BookViewMode.spread, coverAlone: true), [
        [1],
      ]);
    });
  });

  group('BookLayout', () {
    const a4 = Size(100, 140);

    test('scroll stacks the pages in a column', () {
      final l = BookLayout.build(
        [a4, a4, a4],
        mode: BookViewMode.scroll,
        coverAlone: true,
      );
      expect(l.pages[0].top, lessThan(l.pages[1].top));
      expect(l.pages[1].left, l.pages[0].left);
      expect(l.documentSize.height, greaterThan(3 * 140));
    });

    test('single puts pages in a row, each its own unit', () {
      final l = BookLayout.build(
        [a4, a4],
        mode: BookViewMode.single,
        coverAlone: true,
      );
      expect(l.pages[1].left, greaterThan(l.pages[0].right));
      expect(l.unitRect(1), l.pages[1]);
      expect(l.unitOf(2), 1);
    });

    test('spread joins a pair edge to edge', () {
      final l = BookLayout.build(
        [a4, a4, a4],
        mode: BookViewMode.spread,
        coverAlone: true,
      );
      expect(l.units, [
        [1],
        [2, 3],
      ]);
      expect(l.pages[2].left, l.pages[1].right);
      expect(l.unitRect(1).width, 200);
      expect(l.unitOf(3), 1);
    });

    test('pages of different sizes are centred on each other', () {
      final l = BookLayout.build(
        [const Size(100, 100), const Size(100, 200)],
        mode: BookViewMode.spread,
        coverAlone: false,
      );
      expect(l.pages[0].center.dy, l.pages[1].center.dy);
    });

    test('no pages gives an empty layout', () {
      final l = BookLayout.build(
        const [],
        mode: BookViewMode.single,
        coverAlone: true,
      );
      expect(l.pages, isEmpty);
      expect(l.units, isEmpty);
    });
  });

  group('the mode is remembered per book', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('nsl_view_test');
    });
    tearDown(() => tmp.delete(recursive: true));

    BookService make() => BookService(file: File('${tmp.path}\\books.json'));

    test('a new book scrolls with the default fit', () {
      final b = make();
      b.opened('a.pdf', pageCount: 10);
      final s = b.stateOf('a.pdf')!;
      expect(s.viewMode, BookViewMode.scroll);
      expect(s.fit, isNull);
      expect(s.fitFor, BookFit.width);
      b.dispose();
    });

    test('the default fit follows the mode until one is chosen', () {
      final b = make();
      b.opened('a.pdf', pageCount: 10);
      b.saveView('a.pdf', mode: BookViewMode.single, coverAlone: true);
      expect(b.stateOf('a.pdf')!.fitFor, BookFit.page);
      b.saveView(
        'a.pdf',
        mode: BookViewMode.single,
        fit: BookFit.actual,
        coverAlone: true,
      );
      expect(b.stateOf('a.pdf')!.fitFor, BookFit.actual);
      b.dispose();
    });

    test(
      'mode, fit and cover survive a restart; other books are unaffected',
      () async {
        final b = make();
        b.opened('a.pdf', pageCount: 10);
        b.opened('b.pdf', pageCount: 10);
        b.saveView(
          'a.pdf',
          mode: BookViewMode.spread,
          fit: BookFit.width,
          coverAlone: false,
        );
        await b.save();
        b.dispose();

        final again = make();
        final a = again.stateOf('a.pdf')!;
        expect(a.viewMode, BookViewMode.spread);
        expect(a.fit, BookFit.width);
        expect(a.coverAlone, isFalse);
        expect(again.stateOf('b.pdf')!.viewMode, BookViewMode.scroll);
        again.dispose();
      },
    );

    test('unknown values in the file fall back to the defaults', () {
      File('${tmp.path}\\books.json').writeAsStringSync(
        '[{"path":"a.pdf","page":3,"count":9,"opened":5,'
        '"view":"hologram","fit":"zoomy","cover":"yes"}]',
      );
      final s = make().stateOf('a.pdf')!;
      expect(s.page, 3);
      expect(s.viewMode, BookViewMode.scroll);
      expect(s.fit, isNull);
      expect(s.coverAlone, isTrue);
    });
  });
}
