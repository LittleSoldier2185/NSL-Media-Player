import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A page you marked in a book.
class Bookmark {
  Bookmark({required this.page, required this.label, int? created})
    : created = created ?? DateTime.now().millisecondsSinceEpoch;

  final int page;
  String label;
  final int created;

  Map<String, dynamic> toJson() => {'p': page, 'l': label, 'c': created};

  static Bookmark? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['p'], l = j['l'];
    if (p is! int || l is! String) return null;
    return Bookmark(page: p, label: l, created: j['c'] is int ? j['c'] : null);
  }
}

/// What the app remembers about one book: where you stopped and your marks.
class BookState {
  BookState({
    required this.path,
    this.page = 1,
    this.pageCount = 0,
    this.opened = 0,
    List<Bookmark>? bookmarks,
  }) : bookmarks = bookmarks ?? [];

  final String path;

  /// Page you were on (1-based).
  int page;

  /// Number of pages (0 until the book has been opened once).
  int pageCount;

  /// When it was last opened (ms since epoch); 0 = never.
  int opened;
  final List<Bookmark> bookmarks;

  /// 0..1 of the way through, or 0 when the length is not known yet.
  double get progress =>
      pageCount <= 1 ? 0 : ((page - 1) / (pageCount - 1)).clamp(0.0, 1.0);

  bool get started => opened > 0 && page > 1;

  /// Read to (nearly) the last page.
  bool get finished => pageCount > 1 && page >= pageCount;

  Map<String, dynamic> toJson() => {
    'path': path,
    'page': page,
    'count': pageCount,
    'opened': opened,
    if (bookmarks.isNotEmpty) 'marks': [for (final b in bookmarks) b.toJson()],
  };

  static BookState? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['path'];
    if (path is! String) return null;
    return BookState(
      path: path,
      page: j['page'] is int ? (j['page'] as int).clamp(1, 1 << 30) : 1,
      pageCount: j['count'] is int ? j['count'] as int : 0,
      opened: j['opened'] is int ? j['opened'] as int : 0,
      bookmarks: [
        if (j['marks'] is List)
          for (final m in j['marks'] as List)
            if (Bookmark.fromJson(m) case final b?) b,
      ],
    );
  }
}

/// Reading position and bookmarks for every PDF book, kept in
/// `%APPDATA%\NSL Media Player\books.json`. Keyed by file path, so moving a
/// file forgets its place (the file itself is never changed).
class BookService extends ChangeNotifier {
  /// [file] overrides the storage location (used by tests).
  BookService({File? file, this.fileName = 'books.json'})
    : _fileOverride = file {
    _load();
  }

  /// The file's name inside the app's data folder.
  final String fileName;

  final File? _fileOverride;
  final Map<String, BookState> _books = {};
  Timer? _saveTimer;

  File? get _file {
    if (_fileOverride != null) return _fileOverride;
    final base = Platform.environment['APPDATA'];
    return base == null ? null : File('$base\\NSL Media Player\\$fileName');
  }

  static String _key(String path) => path.toLowerCase();

  void _load() {
    try {
      final f = _file;
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is List) {
        for (final e in j) {
          final b = BookState.fromJson(e);
          if (b != null) _books[_key(b.path)] = b;
        }
      }
    } on Object catch (e) {
      debugPrint('Could not read books: $e');
    }
  }

  /// What is remembered about [path], or null if it was never opened.
  BookState? stateOf(String path) => _books[_key(path)];

  BookState _ensure(String path) =>
      _books.putIfAbsent(_key(path), () => BookState(path: path));

  /// Books opened before, most recent first.
  List<BookState> get recent {
    final out = [
      for (final b in _books.values)
        if (b.opened > 0) b,
    ];
    out.sort((a, b) => b.opened.compareTo(a.opened));
    return out;
  }

  /// Books you started and have not finished, most recent first.
  List<BookState> get inProgress => [
    for (final b in recent)
      if (b.started && !b.finished) b,
  ];

  /// Remembers that [path] was opened now (and how long it is).
  void opened(String path, {int? pageCount}) {
    final b = _ensure(path);
    b.opened = DateTime.now().millisecondsSinceEpoch;
    if (pageCount != null && pageCount > 0) {
      b.pageCount = pageCount;
      if (b.page > pageCount) b.page = pageCount;
    }
    _changed();
  }

  /// Remembers the page you are on.
  void savePage(String path, int page, {int? pageCount}) {
    final b = _ensure(path);
    if (pageCount != null && pageCount > 0) b.pageCount = pageCount;
    final p = page.clamp(1, b.pageCount > 0 ? b.pageCount : 1 << 30);
    if (b.page == p && b.opened > 0) return;
    b.page = p;
    if (b.opened == 0) b.opened = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  /// Forgets the reading position (bookmarks stay).
  void markUnread(String path) {
    final b = _books[_key(path)];
    if (b == null) return;
    b.page = 1;
    b.opened = 0;
    _changed();
  }

  // ---- bookmarks ----

  List<Bookmark> bookmarksOf(String path) {
    final out = [...?stateOf(path)?.bookmarks];
    out.sort((a, b) => a.page.compareTo(b.page));
    return out;
  }

  bool hasBookmark(String path, int page) =>
      stateOf(path)?.bookmarks.any((b) => b.page == page) ?? false;

  /// Marks [page]; does nothing if it is already marked.
  void addBookmark(String path, int page, {String? label}) {
    if (hasBookmark(path, page)) return;
    _ensure(path).bookmarks.add(
      Bookmark(
        page: page,
        label: (label == null || label.trim().isEmpty)
            ? 'Page $page'
            : label.trim(),
      ),
    );
    _changed();
  }

  void removeBookmark(String path, int page) {
    final b = stateOf(path);
    if (b == null) return;
    b.bookmarks.removeWhere((m) => m.page == page);
    _changed();
  }

  /// Adds the mark, or removes it when the page already has one. Returns
  /// true when the page is marked afterwards.
  bool toggleBookmark(String path, int page) {
    if (hasBookmark(path, page)) {
      removeBookmark(path, page);
      return false;
    }
    addBookmark(path, page);
    return true;
  }

  void renameBookmark(String path, int page, String label) {
    final n = label.trim();
    if (n.isEmpty) return;
    for (final m in stateOf(path)?.bookmarks ?? const <Bookmark>[]) {
      if (m.page == page) m.label = n;
    }
    _changed();
  }

  // ---- saving ----

  void _changed() {
    notifyListeners();
    // Pages change as fast as you scroll: write once things settle.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
  }

  /// Forgets every place and bookmark.
  Future<void> clear() async {
    _books.clear();
    await save();
    notifyListeners();
  }

  /// Writes to disk now (also called when a reader closes).
  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final f = _file;
      if (f == null) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode([
          for (final b in _books.values)
            if (b.opened > 0 || b.bookmarks.isNotEmpty) b.toJson(),
        ]),
      );
    } on Object catch (e) {
      debugPrint('Could not write books: $e');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
