import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/thumbnail_service.dart';
import 'theme.dart';

/// Preview picture of any media file: cover art for music, a frame for
/// videos, and an icon until (or unless) a picture is available.
///
/// Pictures are cached by path and modification time, so the same file shows
/// the same cached picture wherever it appears (Library, Continue, playlists,
/// queue).
class PathThumb extends StatefulWidget {
  const PathThumb({
    super.key,
    required this.path,
    required this.thumbnails,
    this.modified,
    this.fit = BoxFit.cover,
    this.iconSize = 20,
  });

  final String path;
  final ThumbnailService thumbnails;

  /// File modification time (ms); read from the file when not given.
  final int? modified;
  final BoxFit fit;
  final double iconSize;

  @override
  State<PathThumb> createState() => _PathThumbState();
}

class _PathThumbState extends State<PathThumb> {
  ThumbTicket? _ticket;

  @override
  void initState() {
    super.initState();
    _ticket = _request();
  }

  /// Null when the file is gone: there is nothing to make a picture from.
  ThumbTicket? _request() {
    var modified = widget.modified;
    if (modified == null) {
      try {
        final stat = File(widget.path).statSync();
        if (stat.type == FileSystemEntityType.notFound) return null;
        modified = stat.modified.millisecondsSinceEpoch;
      } on Object {
        return null;
      }
    }
    return widget.thumbnails.request(widget.path, modified);
  }

  @override
  void didUpdateWidget(PathThumb old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.modified != widget.modified) {
      _ticket?.cancel();
      _ticket = _request();
    }
  }

  @override
  void dispose() {
    // Rows scrolled out of view must not keep the decoder busy.
    _ticket?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isVideo = videoExtensions.contains(extensionOf(widget.path));
    final fallback = Center(
      child: Icon(
        isVideo ? Icons.movie_outlined : Icons.music_note,
        size: widget.iconSize,
        color: p.textDim,
      ),
    );
    final ticket = _ticket;
    return ColoredBox(
      color: p.track,
      child: ticket == null
          ? fallback
          : FutureBuilder<Uint8List?>(
              future: ticket.future,
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

/// [PathThumb] for a library item (its modification time is already known).
class LibraryThumb extends StatelessWidget {
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
  Widget build(BuildContext context) => PathThumb(
    path: item.path,
    modified: item.modified,
    thumbnails: library.thumbnails,
    fit: fit,
    iconSize: iconSize,
  );
}
