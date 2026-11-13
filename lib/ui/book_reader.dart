import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../player_controller/player_controller.dart';
import '../services/book_service.dart';
import '../services/thumbnail_service.dart';
import 'now_playing_dock.dart';
import 'shortcut_guard.dart';
import 'file_menu.dart';
import 'theme.dart';
import 'title_bar.dart';

enum _Side { pages, marks, contents }

/// The PDF reader: pages you scroll through, a side panel (page thumbnails,
/// your bookmarks, the table of contents), text search, zoom and dark pages.
/// Where you stopped is saved as you read and restored next time.
class BookReaderPage extends StatefulWidget {
  const BookReaderPage({
    super.key,
    required this.path,
    required this.title,
    required this.books,
    this.thumbnails,
    this.controller,
    this.onOpenPlayer,
  });

  final String path;
  final String title;
  final BookService books;

  /// With [controller]: what plays under the reader keeps its bar.
  final ThumbnailService? thumbnails;
  final NslPlayerController? controller;
  final VoidCallback? onOpenPlayer;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage> {
  static const _paper = Color(0xFF1A1B20);

  final _pdf = PdfViewerController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_pdf)
    ..addListener(_onSearch);
  final _query = TextEditingController();
  final _queryFocus = FocusNode();

  late int _page;
  late int _pages;
  double? _drag; // slider value while dragging

  bool _showSide = true;
  _Side _side = _Side.pages;
  bool _searching = false;
  bool _dark = false;
  List<PdfOutlineNode> _outline = const [];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.books.stateOf(widget.path);
    _page = saved?.page ?? 1;
    _pages = saved?.pageCount ?? 0;
    widget.books.addListener(_onBooks);
  }

  @override
  void dispose() {
    widget.books.removeListener(_onBooks);
    widget.books.save();
    _searcher.removeListener(_onSearch);
    _searcher.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _onBooks() {
    if (mounted) setState(() {});
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  // ---- document events ----

  void _ready(PdfDocument doc, PdfViewerController c) {
    final n = doc.pages.length;
    widget.books.opened(widget.path, pageCount: n);
    if (!mounted) return;
    setState(() => _pages = n);
    doc.loadOutline().then((o) {
      if (mounted) setState(() => _outline = o);
    }, onError: (Object _) {});
  }

  void _pageChanged(int? n) {
    if (n == null || !mounted) return;
    setState(() => _page = n);
    widget.books.savePage(widget.path, n, pageCount: _pages);
  }

  void _goTo(int n) {
    if (!_pdf.isReady) return;
    _pdf.goToPage(pageNumber: n.clamp(1, _pages > 0 ? _pages : n));
  }

  // ---- search ----

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queryFocus.requestFocus();
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
    });
  }

  void _closeSearch() {
    _searcher.resetTextSearch();
    setState(() => _searching = false);
  }

  void _runSearch(String text) {
    if (text.trim().isEmpty) {
      _searcher.resetTextSearch();
    } else {
      _searcher.startTextSearch(text.trim());
    }
  }

  // ---- keys ----

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && k == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_searching) {
        _closeSearch();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    if (textFieldHasFocus()) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyB) {
      _toggleMark();
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      if (_pdf.isReady) _pdf.zoomUp();
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      if (_pdf.isReady) _pdf.zoomDown();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _toggleMark() => widget.books.toggleBookmark(widget.path, _page);

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Column(
          children: [
            NslTitleBar(
              title: 'Books / ${widget.title}',
              onLogo: () => Navigator.of(context).maybePop(),
            ),
            _toolbar(p),
            Expanded(
              child: Row(
                children: [
                  if (_showSide) _sidePanel(p),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _viewer()),
                        if (_searching)
                          Positioned(right: 22, top: 18, child: _searchBox(p)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _pageBar(p),
            if (widget.controller != null && widget.thumbnails != null)
              NowPlayingDock(
                controller: widget.controller!,
                thumbnails: widget.thumbnails!,
                onOpenPlayer: () {
                  Navigator.of(context).maybePop();
                  widget.onOpenPlayer?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  static const _invert = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ]);

  Widget _viewer() {
    if (_failed) {
      return const Center(
        child: Text(
          "Can't open this PDF (damaged, or protected with a password).",
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return PdfViewer.file(
      widget.path,
      controller: _pdf,
      initialPageNumber: _page,
      params: PdfViewerParams(
        backgroundColor: _paper,
        pageImageColorFilter: _dark ? _invert : null,
        onViewerReady: _ready,
        onPageChanged: _pageChanged,
        pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
        onDocumentChanged: (doc) {
          if (doc == null && mounted && _pages == 0) {
            setState(() => _failed = true);
          }
        },
      ),
    );
  }

  Widget _toolButton(
    NslPalette p, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    String? label,
    bool on = false,
  }) {
    final color = on ? p.accent : p.text;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 40),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: on ? p.accent.withValues(alpha: 0.16) : p.track,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, color: color)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(NslPalette p) {
    final marked = widget.books.hasBookmark(widget.path, _page);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.panelTop,
        border: Border(bottom: BorderSide(color: p.panelBorder)),
      ),
      child: Row(
        children: [
          _toolButton(
            p,
            icon: Icons.chevron_left,
            label: 'Books',
            tooltip: 'Back to the shelf (Esc)',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          _toolButton(
            p,
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Pages, bookmarks and contents',
            on: _showSide,
            onTap: () => setState(() => _showSide = !_showSide),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
            ),
          ),
          _toolButton(
            p,
            icon: Icons.search,
            label: 'Search',
            tooltip: 'Search the text (Ctrl+F)',
            on: _searching,
            onTap: () => _searching ? _closeSearch() : _openSearch(),
          ),
          const SizedBox(width: 6),
          _toolButton(
            p,
            icon: marked ? Icons.bookmark : Icons.bookmark_border,
            label: 'Bookmark',
            tooltip: 'Bookmark this page (B)',
            on: marked,
            onTap: _toggleMark,
          ),
          const SizedBox(width: 6),
          _toolButton(
            p,
            icon: Icons.remove,
            tooltip: 'Zoom out (-)',
            onTap: () {
              if (_pdf.isReady) _pdf.zoomDown();
            },
          ),
          const SizedBox(width: 6),
          _toolButton(
            p,
            icon: Icons.add,
            tooltip: 'Zoom in (+)',
            onTap: () {
              if (_pdf.isReady) _pdf.zoomUp();
            },
          ),
          const SizedBox(width: 6),
          _toolButton(
            p,
            icon: Icons.contrast,
            label: 'Dark pages',
            tooltip: 'Invert the page colours',
            on: _dark,
            onTap: () => setState(() => _dark = !_dark),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            tooltip: 'File',
            onSelected: (v) => runFileCommand(context, v, widget.path),
            itemBuilder: (_) => fileMenuItems(divider: false),
            child: Container(
              height: 36,
              width: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: p.track,
              ),
              child: Icon(Icons.folder_open, size: 18, color: p.text),
            ),
          ),
        ],
      ),
    );
  }

  // ---- side panel ----

  Widget _sidePanel(NslPalette p) {
    Widget tab(_Side s, String label) {
      final on = _side == s;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _side = s),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: on ? p.accent.withValues(alpha: 0.14) : p.track,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? p.accent : p.text,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
      decoration: BoxDecoration(
        color: p.panelTop,
        border: Border(right: BorderSide(color: p.panelBorder)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              tab(_Side.pages, 'Pages'),
              const SizedBox(width: 6),
              tab(_Side.marks, 'Marks'),
              const SizedBox(width: 6),
              tab(_Side.contents, 'Contents'),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: switch (_side) {
              _Side.pages => _pageThumbs(p),
              _Side.marks => _marks(p),
              _Side.contents => _contents(p),
            },
          ),
        ],
      ),
    );
  }

  Widget _pageThumbs(NslPalette p) {
    return PdfDocumentViewBuilder.file(
      widget.path,
      builder: (context, doc) {
        if (doc == null) return const SizedBox.shrink();
        return ListView.separated(
          itemCount: doc.pages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final n = i + 1;
            final here = n == _page;
            return GestureDetector(
              onTap: () => _goTo(n),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  children: [
                    Container(
                      width: 120,
                      height: 156,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          if (here) BoxShadow(color: p.accent, spreadRadius: 3),
                        ],
                      ),
                      child: PdfPageView(
                        document: doc,
                        pageNumber: n,
                        maximumDpi: 90,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 12,
                        color: here ? p.accent : p.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _marks(NslPalette p) {
    final marks = widget.books.bookmarksOf(widget.path);
    if (marks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No bookmarks yet. Press B (or the Bookmark button) to mark a page.',
          style: TextStyle(fontSize: 12.5, color: p.textDim),
        ),
      );
    }
    return ListView(
      children: [
        for (final m in marks)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: Icon(Icons.bookmark, size: 18, color: p.accent),
            title: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Page ${m.page}'),
            onTap: () => _goTo(m.page),
            trailing: IconButton(
              tooltip: 'Remove bookmark',
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => widget.books.removeBookmark(widget.path, m.page),
            ),
          ),
      ],
    );
  }

  Widget _contents(NslPalette p) {
    if (_outline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'This book has no table of contents.',
          style: TextStyle(fontSize: 12.5, color: p.textDim),
        ),
      );
    }
    final rows = <Widget>[];
    void add(PdfOutlineNode n, int depth) {
      rows.add(
        InkWell(
          onTap: () {
            if (_pdf.isReady) _pdf.goToDest(n.dest);
          },
          child: Padding(
            padding: EdgeInsets.fromLTRB(6.0 + depth * 14, 7, 6, 7),
            child: Text(n.title, style: TextStyle(fontSize: 13, color: p.text)),
          ),
        ),
      );
      for (final c in n.children) {
        add(c, depth + 1);
      }
    }

    for (final n in _outline) {
      add(n, 0);
    }
    return ListView(children: rows);
  }

  // ---- search box ----

  Widget _searchBox(NslPalette p) {
    final n = _searcher.matches.length;
    final i = _searcher.currentIndex;
    final status = _query.text.trim().isEmpty
        ? ''
        : _searcher.isSearching && n == 0
        ? 'Searching…'
        : n == 0
        ? 'No matches'
        : '${(i ?? 0) + 1} of $n${_searcher.isSearching ? '…' : ''}';
    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.panelTop,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _query,
            focusNode: _queryFocus,
            onChanged: _runSearch,
            onSubmitted: (_) => _searcher.goToNextMatch(),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search the text',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixText: status,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: p.accent),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: p.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: n == 0 ? null : _searcher.goToPrevMatch,
                  child: const Text('‹ Previous'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: n == 0 ? null : _searcher.goToNextMatch,
                  child: const Text('Next ›'),
                ),
              ),
              IconButton(
                tooltip: 'Close search (Esc)',
                onPressed: _closeSearch,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- bottom bar ----

  Widget _pageBar(NslPalette p) {
    final total = _pages;
    final shown = (_drag ?? _page.toDouble()).round();
    final pct = total <= 1 ? 0 : (((shown - 1) / (total - 1)) * 100).round();
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: p.panelTop,
        border: Border(top: BorderSide(color: p.panelBorder)),
      ),
      child: Row(
        children: [
          Text(
            total > 0 ? 'Page $shown of $total' : 'Page $shown',
            style: TextStyle(fontSize: 13, color: p.text),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: total > 1
                ? Slider(
                    min: 1,
                    max: total.toDouble(),
                    divisions: total - 1,
                    value: (_drag ?? _page.toDouble()).clamp(
                      1,
                      total.toDouble(),
                    ),
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      setState(() => _drag = null);
                      _goTo(v.round());
                    },
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Text('$pct%', style: TextStyle(fontSize: 13, color: p.textDim)),
          const SizedBox(width: 16),
          Text(
            'Saved automatically',
            style: TextStyle(fontSize: 13, color: p.textDim),
          ),
        ],
      ),
    );
  }
}
