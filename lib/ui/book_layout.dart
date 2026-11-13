import 'dart:math' as math;
import 'dart:ui';

import '../services/book_service.dart';

/// Where every page of a book sits for a [BookViewMode], and the "units" you
/// turn between: one page (single), a pair (spread), or a page (scroll).
class BookLayout {
  BookLayout._(this.pages, this.units, this.documentSize);

  /// Page rectangles (index 0 = page 1), in document coordinates.
  final List<Rect> pages;

  /// For each unit, the page numbers (1-based) in it.
  final List<List<int>> units;

  final Size documentSize;

  /// Index of the unit that holds [page] (1-based); 0 for a page out of range.
  int unitOf(int page) {
    for (var i = 0; i < units.length; i++) {
      if (units[i].contains(page)) return i;
    }
    return 0;
  }

  /// The area of unit [index] (its pages together).
  Rect unitRect(int index) {
    final nums = units[index.clamp(0, units.length - 1)];
    return nums.map((n) => pages[n - 1]).reduce((a, b) => a.expandToInclude(b));
  }

  /// Lays out pages of the given [sizes].
  ///
  /// Scroll: a vertical column, centred. Single: pages side by side in a
  /// row. Spread: pairs side by side with no gap inside a pair; the first
  /// page stands alone when [coverAlone].
  factory BookLayout.build(
    List<Size> sizes, {
    required BookViewMode mode,
    required bool coverAlone,
    double margin = 8,
  }) {
    final n = sizes.length;
    if (n == 0) return BookLayout._(const [], const [], Size.zero);
    final rects = List<Rect>.filled(n, Rect.zero);
    final units = groupPages(n, mode: mode, coverAlone: coverAlone);

    if (mode == BookViewMode.scroll) {
      final width = sizes.fold<double>(0, (m, s) => math.max(m, s.width));
      var y = margin;
      for (var i = 0; i < n; i++) {
        rects[i] = Rect.fromLTWH(
          margin + (width - sizes[i].width) / 2,
          y,
          sizes[i].width,
          sizes[i].height,
        );
        y += sizes[i].height + margin;
      }
      return BookLayout._(rects, units, Size(width + margin * 2, y));
    }

    final height = sizes.fold<double>(0, (m, s) => math.max(m, s.height));
    var x = margin;
    for (final unit in units) {
      for (final num in unit) {
        final s = sizes[num - 1];
        rects[num - 1] = Rect.fromLTWH(
          x,
          margin + (height - s.height) / 2,
          s.width,
          s.height,
        );
        x += s.width;
      }
      x += margin * 2; // a clear gap between units
    }
    return BookLayout._(rects, units, Size(x - margin, height + margin * 2));
  }
}

/// The page numbers (1-based) that are shown together.
List<List<int>> groupPages(
  int count, {
  required BookViewMode mode,
  required bool coverAlone,
}) {
  if (mode != BookViewMode.spread) {
    return [
      for (var i = 1; i <= count; i++) [i],
    ];
  }
  final out = <List<int>>[];
  var i = 1;
  if (coverAlone && count > 0) {
    out.add([1]);
    i = 2;
  }
  while (i <= count) {
    out.add([i, if (i + 1 <= count) i + 1]);
    i += 2;
  }
  return out;
}
