import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/thumbnail_service.dart';
import 'theme.dart';

/// Preview picture of a library file: cover art for music, a frame for
/// videos, and an icon until (or unless) a picture is available.
class LibraryThumb extends StatefulWidget {
  const LibraryThumb({
    super.key,
    required this.item,
    required this.library,
    this.fit = BoxFit.cover,
    this.iconSize = 20,
  });

  final LibraryItem item;
  final LibraryService library;
  final BoxFit fit;
  final double iconSize;

  @override
  State<LibraryThumb> createState() => _LibraryThumbState();
}

class _LibraryThumbState extends State<LibraryThumb> {
  late ThumbTicket _ticket;

  @override
  void initState() {
    super.initState();
    _ticket = _request();
  }

  ThumbTicket _request() =>
      widget.library.thumbnails.request(widget.item.path, widget.item.modified);

  @override
  void didUpdateWidget(LibraryThumb old) {
    super.didUpdateWidget(old);
    if (old.item.path != widget.item.path ||
        old.item.modified != widget.item.modified) {
      _ticket.cancel();
      _ticket = _request();
    }
  }

  @override
  void dispose() {
    // Rows scrolled out of view must not keep the decoder busy.
    _ticket.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fallback = Center(
      child: Icon(
        widget.item.isVideo ? Icons.movie_outlined : Icons.music_note,
        size: widget.iconSize,
        color: p.textDim,
      ),
    );
    return ColoredBox(
      color: p.track,
      child: FutureBuilder<Uint8List?>(
        future: _ticket.future,
        builder: (_, s) {
          final b = s.data;
          if (b == null) return fallback;
          return Image.memory(
            b,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: ThumbnailService.thumbWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          );
        },
      ),
    );
  }
}
