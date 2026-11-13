import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/book_service.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import 'book_reader.dart';
import 'library_thumb.dart';
import 'file_menu.dart';
import 'theme.dart';

enum _Filter { all, reading, notStarted, finished }

enum _Sort { recent, title, progress }

/// Books: your PDFs as a shelf of covers with how far you got in each, a
/// "Continue reading" card, and a reader (see [BookReaderPage]).
class BooksView extends StatefulWidget {
  const BooksView({
    super.key,
    required this.library,
    required this.books,
    required this.onOpenLibrary,
    this.controller,
    this.onOpenPlayer,
  });

  final LibraryService library;

  /// Where you stopped and your bookmarks.
  final BookService books;
  final VoidCallback onOpenLibrary;

  /// The player, to show what is playing under the reader (none in tests).
  final NslPlayerController? controller;
  final VoidCallback? onOpenPlayer;

  @override
  State<BooksView> createState() => _BooksViewState();
}

class _BooksViewState extends State<BooksView> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---- what to show ----

  BookState? _state(LibraryItem b) => widget.books.stateOf(b.path);

  bool _isReading(BookState? s) => s != null && s.started && !s.finished;

  List<LibraryItem> _shown() {
    final q = _search.text.trim().toLowerCase();
    final out = [
      for (final b in widget.library.books)
        if ((q.isEmpty ||
                b.title.toLowerCase().contains(q) ||
                b.path.toLowerCase().contains(q)) &&
            switch (_filter) {
              _Filter.all => true,
              _Filter.reading => _isReading(_state(b)),
              _Filter.notStarted => !(_state(b)?.started ?? false),
              _Filter.finished => _state(b)?.finished ?? false,
            })
          b,
    ];
    int title(LibraryItem a, LibraryItem b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (_sort) {
      case _Sort.title:
        out.sort(title);
      case _Sort.recent:
        out.sort((a, b) {
          final c = (_state(b)?.opened ?? 0).compareTo(_state(a)?.opened ?? 0);
          return c != 0 ? c : title(a, b);
        });
      case _Sort.progress:
        out.sort((a, b) {
          final c = (_state(b)?.progress ?? 0).compareTo(
            _state(a)?.progress ?? 0,
          );
          return c != 0 ? c : title(a, b);
        });
    }
    return out;
  }

  // ---- actions ----

  void _open(String path, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookReaderPage(
          path: path,
          title: title,
          books: widget.books,
          thumbnails: widget.library.thumbnails,
          controller: widget.controller,
          onOpenPlayer: widget.onOpenPlayer,
        ),
      ),
    );
  }

  Future<void> _openFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = r?.files.single.path;
    if (path == null || !mounted) return;
    final n = fileNameOf(path);
    _open(
      path,
      n.toLowerCase().endsWith('.pdf') ? n.substring(0, n.length - 4) : n,
    );
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) await widget.library.addFolder(dir);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.library, widget.books]),
      builder: (context, _) {
        final all = widget.library.books;
        final shown = _shown();
        final resume = _resumeItem();
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(p, all.length),
              const SizedBox(height: 16),
              Expanded(
                child: all.isEmpty
                    ? _empty(p)
                    : CustomScrollView(
                        slivers: [
                          if (resume != null &&
                              _filter == _Filter.all &&
                              _search.text.trim().isEmpty)
                            SliverToBoxAdapter(child: _resumeCard(p, resume)),
                          if (shown.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 40),
                                child: Center(
                                  child: Text(
                                    'No books match.',
                                    style: TextStyle(color: p.textDim),
                                  ),
                                ),
                              ),
                            )
                          else
                            _grid(shown),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The book "Continue reading" offers: the one you read last, if unfinished.
  LibraryItem? _resumeItem() {
    for (final s in widget.books.inProgress) {
      for (final b in widget.library.books) {
        if (b.path.toLowerCase() == s.path.toLowerCase()) return b;
      }
    }
    return null;
  }

  Widget _header(NslPalette p, int count) {
    final search = SizedBox(
      width: 220,
      height: 36,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search title',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: p.track,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: p.border),
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Books',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: p.text,
          ),
        ),
        if (count > 0)
          Text('$count', style: TextStyle(fontSize: 14, color: p.textDim)),
        const SizedBox(width: 6),
        for (final f in _Filter.values) _chip(p, f),
        search,
        PopupMenuButton<_Sort>(
          tooltip: 'Sort',
          initialValue: _sort,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (_) => const [
            PopupMenuItem(value: _Sort.recent, child: Text('Recently read')),
            PopupMenuItem(value: _Sort.title, child: Text('Title')),
            PopupMenuItem(value: _Sort.progress, child: Text('Progress')),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: p.track,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.border),
            ),
            alignment: Alignment.center,
            child: Text(switch (_sort) {
              _Sort.recent => 'Recently read ▾',
              _Sort.title => 'Title ▾',
              _Sort.progress => 'Progress ▾',
            }, style: TextStyle(fontSize: 13, color: p.text)),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openFile,
          icon: const Icon(Icons.file_open_outlined, size: 18),
          label: const Text('Open PDF'),
        ),
        FilledButton.icon(
          onPressed: _addFolder,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add folder'),
        ),
      ],
    );
  }

  Widget _chip(NslPalette p, _Filter f) {
    final on = _filter == f;
    final label = switch (f) {
      _Filter.all => 'All',
      _Filter.reading => 'Reading',
      _Filter.notStarted => 'Not started',
      _Filter.finished => 'Finished',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _filter = f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: on ? p.accent : p.track,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: on ? p.onAccent : p.text,
          ),
        ),
      ),
    );
  }

  Widget _empty(NslPalette p) {
    final noFolders = widget.library.folders.isEmpty;
    final message = widget.library.scanning
        ? 'Looking through your library folders…'
        : noFolders
        ? 'Add a folder (or open a PDF) and your books will show up here.'
        : 'No PDF books found in your library folders.';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: p.textDim),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: p.textDim),
            ),
            if (noFolders && !widget.library.scanning) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: widget.onOpenLibrary,
                child: const Text('Open Library'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resumeCard(NslPalette p, LibraryItem b) {
    final s = _state(b)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.panelBorder),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.panelTop, p.panelBottom],
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 96, height: 128, child: _cover(b, null, p)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONTINUE READING',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    color: p.textDim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  b.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Page ${s.page}${s.pageCount > 0 ? ' of ${s.pageCount}' : ''}'
                  ' · ${_ago(s.opened)}',
                  style: TextStyle(color: p.textDim),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: s.progress,
                      minHeight: 5,
                      color: p.accent,
                      backgroundColor: p.track,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: () => _open(b.path, b.title),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  /// "just now", "5 min ago", "yesterday", "3 days ago"...
  static String _ago(int ms, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    if (d.inMinutes < 1) return 'last read just now';
    if (d.inMinutes < 60) return 'last read ${d.inMinutes} min ago';
    if (d.inHours < 24) return 'last read ${d.inHours} h ago';
    if (d.inDays == 1) return 'last read yesterday';
    return 'last read ${d.inDays} days ago';
  }

  /// A book's cover, with a strip showing how far you got along its bottom.
  Widget _cover(LibraryItem b, double? progress, NslPalette p) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PathThumb(
            path: b.path,
            modified: b.modified,
            thumbnails: widget.library.thumbnails,
            fit: BoxFit.cover,
            iconSize: 34,
          ),
          if (progress != null && progress > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: progress,
                  color: p.accent,
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(List<LibraryItem> list) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        const gap = 16.0;
        final cols = (c.crossAxisExtent / 170).floor().clamp(2, 12);
        final w = (c.crossAxisExtent - (cols - 1) * gap) / cols;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: gap,
            mainAxisSpacing: 22,
            mainAxisExtent: w * 4 / 3 + 58,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _card(list[i]),
            childCount: list.length,
          ),
        );
      },
    );
  }

  Widget _card(LibraryItem b) {
    final p = context.pal;
    final s = _state(b);
    final sub = s == null || !s.started
        ? 'Not started'
        : s.finished
        ? 'Finished'
        : 'Page ${s.page}${s.pageCount > 0 ? ' of ${s.pageCount}' : ''}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(b.path, b.title),
        onSecondaryTapUp: (d) =>
            showFileContextMenu(context, d.globalPosition, b.path),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: _cover(b, s?.progress, p),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              b.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.text),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
