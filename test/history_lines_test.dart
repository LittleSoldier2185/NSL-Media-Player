import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/history_service.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/ui/history_view.dart';
import 'package:nsl_media_player/ui/time_format.dart';

HistoryEntry entry(String path, DateTime at) =>
    HistoryEntry(path: path, posMs: 6000, durMs: 20000, lastPlayed: at);

void main() {
  final now = DateTime(2026, 11, 12, 15);
  final entries = [
    entry(r'D:\v\a.mp4', DateTime(2026, 11, 12, 12)), // today
    entry(r'D:\m\b.mp3', DateTime(2026, 11, 12, 9)), // today
    entry(r'D:\v\c.mp4', DateTime(2026, 11, 11, 21)), // yesterday
    entry(r'D:\m\d.mp3', DateTime(2026, 11, 11, 20)), // yesterday
    entry(r'D:\v\e.mp4', DateTime(2026, 11, 11, 18)), // yesterday
    entry(r'D:\v\f.mp4', DateTime(2026, 11, 9, 10)), // earlier this week
    entry(r'D:\m\old.mp3', DateTime(2026, 10, 1, 10)), // earlier
  ];

  List<HistoryLine> lines({
    HistoryKind kind = HistoryKind.all,
    String query = '',
    Map<String, LibraryItem> byPath = const {},
  }) => buildHistoryLines(
    entries: entries,
    byPath: byPath,
    kind: kind,
    query: query,
    now: now,
  );

  test('groups by day with a heading before each group', () {
    final l = lines();
    final headings = [
      for (final x in l)
        if (x.day != null) x.day,
    ];
    expect(headings, [
      HistoryDay.today,
      HistoryDay.yesterday,
      HistoryDay.thisWeek,
      HistoryDay.earlier,
    ]);
    expect(l.where((x) => x.entry != null).length, entries.length);
    expect(l.first.day, HistoryDay.today); // starts with a heading
  });

  test('rows know their place in the rounded group card', () {
    final rows = [
      for (final x in lines())
        if (x.entry != null) x.position,
    ];
    // today: first, last | yesterday: first, middle, last | week: only | earlier: only
    expect(rows, [1, 3, 1, 2, 3, 0, 0]);
  });

  test('filters by kind', () {
    final v = lines(kind: HistoryKind.videos);
    expect(
      v.where((x) => x.entry != null).every((x) => x.entry!.isVideo),
      isTrue,
    );
    expect(v.where((x) => x.entry != null).length, 4);
    final m = lines(kind: HistoryKind.music);
    expect(m.where((x) => x.entry != null).length, 3);
  });

  test('a filtered group is re-measured (positions stay right)', () {
    final m = lines(kind: HistoryKind.music);
    final rows = [
      for (final x in m)
        if (x.entry != null) x.position,
    ];
    // today: b (only) | yesterday: d (only) | earlier: old (only)
    expect(rows, [0, 0, 0]);
  });

  test('search matches the file name and the library tags', () {
    expect(lines(query: 'a.mp4').where((x) => x.entry != null).length, 1);
    final byPath = {
      r'd:\m\b.mp3': LibraryItem(
        path: r'D:\m\b.mp3',
        title: 'Midnight Drive',
        artist: 'Neon Coast',
        modified: 1,
      ),
    };
    final byTitle = lines(query: 'midnight', byPath: byPath);
    expect(
      byTitle.where((x) => x.entry != null).single.entry!.path,
      r'D:\m\b.mp3',
    );
    final byArtist = lines(query: 'neon', byPath: byPath);
    expect(byArtist.where((x) => x.entry != null).length, 1);
  });

  test('no matches gives an empty list (no stray headings)', () {
    expect(lines(query: 'zzz'), isEmpty);
    expect(
      buildHistoryLines(
        entries: const [],
        byPath: const {},
        kind: HistoryKind.all,
        now: now,
      ),
      isEmpty,
    );
  });
}
