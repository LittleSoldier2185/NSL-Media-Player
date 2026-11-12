import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/legacy.dart';

import '../services/library_service.dart';
import '../services/playlist_service.dart';
import 'photo_common.dart';
import 'theme.dart';
import 'title_bar.dart';

/// Shows one picture at a time: zoom and pan with the wheel or by dragging,
/// move with the arrow keys or the buttons, details on the right.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.items,
    this.index = 0,
    this.albums,
    this.slideshow = false,
  });

  final List<LibraryItem> items;
  final int index;

  /// Where "Add to album" puts the picture (the button is hidden without it).
  final PlaylistService? albums;

  /// Start playing as a slideshow right away.
  final bool slideshow;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late int _i = widget.index.clamp(0, widget.items.length - 1);
  final _zoom = TransformationController();
  final _focus = FocusNode(debugLabel: 'photo viewer');
  final _strip = ScrollController();
  bool _info = false;
  int _turns = 0; // quarter turns, for looking only (the file is not changed)
  Size? _pixels; // size of the picture in pixels, once loaded

  // Slideshow and fullscreen.
  Timer? _timer;
  bool _playing = false;
  int _every = 5; // seconds per picture
  bool _full = false;

  static const _stripTile = 84.0;

  LibraryItem get _item => widget.items[_i];

  @override
  void initState() {
    super.initState();
    _loadSize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerStrip(false);
      if (widget.slideshow) _startSlideshow();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_full) windowManager.setFullScreen(false);
    _zoom.dispose();
    _focus.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _loadSize() {
    final path = _item.path;
    _pixels = null;
    final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      if (mounted && path == _item.path) {
        setState(() {
          _pixels = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
        });
      }
      stream.removeListener(l);
    }, onError: (_, _) => stream.removeListener(l));
    stream.addListener(l);
  }

  // ---- slideshow / fullscreen ----

  void _startSlideshow() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _every), (_) => _next());
    setState(() => _playing = true);
  }

  void _stopSlideshow() {
    _timer?.cancel();
    _timer = null;
    if (_playing) setState(() => _playing = false);
  }

  void _toggleSlideshow() => _playing ? _stopSlideshow() : _startSlideshow();

  void _setEvery(int seconds) {
    _every = seconds;
    if (_playing) {
      _startSlideshow();
    } else {
      setState(() {});
    }
  }

  /// The slideshow goes round: after the last picture comes the first.
  void _next() => _go(_i >= widget.items.length - 1 ? 0 : _i + 1, wrap: true);

  void _toggleFull() {
    setState(() => _full = !_full);
    windowManager.setFullScreen(_full);
  }

  void _go(int to, {bool wrap = false}) {
    if (widget.items.isEmpty) return;
    final n = to.clamp(0, widget.items.length - 1);
    if (n == _i) return;
    // A click or key of your own: the next automatic step is a full interval
    // away, not a moment after.
    if (_playing && !wrap) _startSlideshow();
    setState(() {
      _i = n;
      _zoom.value = Matrix4.identity();
      _turns = 0;
    });
    _loadSize();
    _centerStrip(true);
    // Have the neighbours ready so the next click is instant.
    for (final k in [n - 1, n + 1]) {
      if (k >= 0 && k < widget.items.length) {
        precacheImage(FileImage(File(widget.items[k].path)), context);
      }
    }
  }

  void _centerStrip(bool animate) {
    if (!_strip.hasClients) return;
    final view = _strip.position.viewportDimension;
    final target = (_i * (_stripTile + 8) - (view - _stripTile) / 2).clamp(
      0.0,
      _strip.position.maxScrollExtent,
    );
    if (animate) {
      _strip.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _strip.jumpTo(target);
    }
  }

  double get _scale => _zoom.value.getMaxScaleOnAxis();

  void _zoomBy(double factor) {
    final s = (_scale * factor).clamp(1.0, 8.0);
    final f = s / _scale;
    if (f == 1) return;
    // Zoom around the middle of what is on screen.
    final box = context.findRenderObject() as RenderBox?;
    final c = box == null ? Offset.zero : box.size.center(Offset.zero);
    _zoom.value = _zoom.value.clone()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    setState(() {});
  }

  void _fit() {
    _zoom.value = Matrix4.identity();
    setState(() {});
  }

  void _toggleZoomAt(Offset p) {
    if (_scale > 1.01) return _fit();
    const f = 2.5;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (f - 1), -p.dy * (f - 1), 0, 1)
      ..scaleByDouble(f, f, 1, 1);
    setState(() {});
  }

  void _rotate() => setState(() => _turns = (_turns + 1) % 4);

  void _showInFolder() {
    Process.run('explorer', ['/select,', _item.path]);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.pageDown) {
      _go(_i + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.pageUp) {
      _go(_i - 1);
    } else if (k == LogicalKeyboardKey.home) {
      _go(0);
    } else if (k == LogicalKeyboardKey.end) {
      _go(widget.items.length - 1);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_full) {
        _toggleFull();
      } else {
        Navigator.of(context).maybePop();
      }
    } else if (k == LogicalKeyboardKey.space) {
      _toggleSlideshow();
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFull();
    } else if (k == LogicalKeyboardKey.keyI) {
      setState(() => _info = !_info);
    } else if (k == LogicalKeyboardKey.keyR) {
      _rotate();
    } else if (k == LogicalKeyboardKey.digit0) {
      _fit();
    } else if (k == LogicalKeyboardKey.equal ||
        k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(1.25);
    } else if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(0.8);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (widget.items.isEmpty) {
      return const Scaffold(body: Center(child: Text('No pictures')));
    }
    final item = _item;
    final when = DateTime.fromMillisecondsSinceEpoch(item.when);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF050607),
        body: Column(
          children: [
            if (!_full)
              NslTitleBar(
                title: '${item.title} · ${_i + 1} of ${widget.items.length}',
                onLogo: () => Navigator.of(context).maybePop(),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _stage()),
                        if (!_full) _toolbar(p),
                        if (!_full) _filmstrip(p),
                      ],
                    ),
                  ),
                  if (_info && !_full) _details(p, item, when),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stage() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTapDown: (d) => _toggleZoomAt(d.localPosition),
            onDoubleTap: () {},
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 8,
              onInteractionEnd: (_) => setState(() {}),
              child: Center(
                child: RotatedBox(
                  quarterTurns: _turns,
                  child: Image.file(
                    File(_item.path),
                    key: ValueKey(_item.path),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      size: 64,
                      color: Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_i > 0)
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _roundButton(Icons.chevron_left, 'Previous (←)', () {
                _go(_i - 1);
              }),
            ),
          ),
        if (_i < widget.items.length - 1)
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _roundButton(Icons.chevron_right, 'Next (→)', () {
                _go(_i + 1);
              }),
            ),
          ),
        Positioned(
          left: 16,
          top: 12,
          child: _pill(Icons.arrow_back, 'Back to Photos', () {
            Navigator.of(context).maybePop();
          }),
        ),
      ],
    );
  }

  Widget _roundButton(IconData icon, String tip, VoidCallback onTap) =>
      Material(
        color: const Color(0xCC14151A),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
          iconSize: 26,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      );

  Widget _pill(IconData icon, String label, VoidCallback onTap) => Material(
    color: const Color(0xCC14151A),
    shape: const StadiumBorder(),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _toolbar(NslPalette p) {
    Widget b(
      IconData icon,
      String tip,
      VoidCallback onTap, {
      bool on = false,
    }) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      color: on ? p.accentInk : const Color(0xFFC9CCD6),
      icon: Icon(icon),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
    return SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          b(
            _playing ? Icons.pause_circle_outline : Icons.slideshow,
            _playing ? 'Pause slideshow (Space)' : 'Slideshow (Space)',
            _toggleSlideshow,
            on: _playing,
          ),
          PopupMenuButton<int>(
            tooltip: 'Time per picture',
            onSelected: _setEvery,
            itemBuilder: (_) => [
              for (final s in const [3, 5, 10, 30])
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == _every,
                  child: Text('$s seconds'),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_every}s',
                style: const TextStyle(color: Color(0xFFC9CCD6)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          b(Icons.zoom_out, 'Zoom out (-)', () => _zoomBy(0.8)),
          b(Icons.zoom_in, 'Zoom in (+)', () => _zoomBy(1.25)),
          b(Icons.fit_screen, 'Fit to window (0)', _fit),
          b(Icons.rotate_right, 'Rotate (R)', _rotate, on: _turns != 0),
          b(Icons.info_outline, 'Details (I)', () {
            setState(() => _info = !_info);
          }, on: _info),
          if (widget.albums != null)
            AddToAlbumButton(
              albums: widget.albums!,
              paths: () => [_item.path],
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.photo_album_outlined,
                  color: Color(0xFFC9CCD6),
                ),
              ),
            ),
          b(Icons.fullscreen, 'Fullscreen (F)', _toggleFull),
          b(Icons.folder_open, 'Show in folder', _showInFolder),
        ],
      ),
    );
  }

  Widget _filmstrip(NslPalette p) {
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0B0D),
        border: Border(top: BorderSide(color: Color(0xFF1B1D23))),
      ),
      child: ListView.separated(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _i;
          return GestureDetector(
            onTap: () => _go(i),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Opacity(
                opacity: selected ? 1 : 0.6,
                child: Container(
                  width: _stripTile,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: selected
                        ? Border.all(color: p.accent, width: 2)
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(widget.items[i].path),
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF1B1D23)),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _bytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    final mb = n / (1024 * 1024);
    return mb < 100 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }

  Widget _details(NslPalette p, LibraryItem item, DateTime when) {
    int? size;
    try {
      size = File(item.path).lengthSync();
    } on Object {
      size = null;
    }
    final slash = math.max(
      item.path.lastIndexOf('\\'),
      item.path.lastIndexOf('/'),
    );
    final folder = slash < 0 ? '' : item.path.substring(0, slash);
    String two(int n) => n.toString().padLeft(2, '0');
    final rows = <(String, String)>[
      (
        item.taken != null ? 'Taken' : 'Changed',
        '${dayLabel(DateTime(when.year, when.month, when.day), DateTime.now())}'
            ', ${two(when.hour)}:${two(when.minute)}',
      ),
      if (_pixels != null)
        ('Size', '${_pixels!.width.round()} × ${_pixels!.height.round()}'),
      ('File', item.path.split('.').last.toUpperCase()),
      if (size != null) ('File size', _bytes(size)),
    ];
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: p.panelBottom,
        border: Border(left: BorderSide(color: p.panelBorder)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DETAILS',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: p.textDim,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fileName(item.path),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(folder, style: TextStyle(fontSize: 12.5, color: p.textDim)),
          const SizedBox(height: 18),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(k, style: TextStyle(fontSize: 13, color: p.textDim)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      v,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, color: p.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String fileName(String path) => path.split(RegExp(r'[\\/]')).last;
}
