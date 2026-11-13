import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';

import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/tag_editor.dart';
import 'theme.dart';

/// Opens the "Edit info" box for [paths] (one song, or several to change
/// their artist, album and cover together). Saved changes are written into the
/// song files and the rows in [library] are refreshed. Returns true when at
/// least one song was changed.
Future<bool> showTagEditor(
  BuildContext context, {
  required List<String> paths,
  required LibraryService library,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => TagDialog(paths: paths, library: library),
  );
  return done ?? false;
}

class TagDialog extends StatefulWidget {
  const TagDialog({super.key, required this.paths, required this.library});

  final List<String> paths;
  final LibraryService library;

  @override
  State<TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<TagDialog> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _album = TextEditingController();

  late final List<String> _paths = [
    for (final p in widget.paths)
      if (canEditTags(p)) p,
  ];
  int get _skipped => widget.paths.length - _paths.length;
  bool get _multi => _paths.length > 1;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // What the files held when the box opened (to see what was changed).
  String _title0 = '', _artist0 = '', _album0 = '';
  bool _sameTitle = true, _sameArtist = true, _sameAlbum = true;

  /// The cover the song has now (single song), a new one, or "remove".
  Uint8List? _currentCover;
  Uint8List? _newCover;
  bool _removeCover = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await Future.wait([for (final p in _paths) readTagValues(p)]);
    if (!mounted) return;
    if (all.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    String common(String Function(TagValues) f, void Function(bool) same) {
      final first = f(all.first);
      final allSame = all.every((v) => f(v) == first);
      same(allSame);
      return allSame ? first : '';
    }

    setState(() {
      _title0 = common((v) => v.title, (s) => _sameTitle = s);
      _artist0 = common((v) => v.artist, (s) => _sameArtist = s);
      _album0 = common((v) => v.album, (s) => _sameAlbum = s);
      _title.text = _title0;
      _artist.text = _artist0;
      _album.text = _album0;
      if (!_multi) _currentCover = all.first.cover;
      _loading = false;
    });
  }

  // ---- cover ----

  Future<void> _chooseCover() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    final path = r?.files.single.path;
    if (path == null) return;
    await _setCoverFrom(() => File(path).readAsBytes());
  }

  Future<void> _pasteCover() async {
    await _setCoverFrom(() async {
      final img = await Pasteboard.image;
      if (img != null && img.isNotEmpty) return img;
      // A picture file copied in File Explorer.
      for (final f in await Pasteboard.files()) {
        if (const {'jpg', 'jpeg', 'png'}.contains(extensionOf(f))) {
          return File(f).readAsBytes();
        }
      }
      return null;
    }, nothing: 'There is no picture on the clipboard.');
  }

  Future<void> _setCoverFrom(
    Future<Uint8List?> Function() read, {
    String? nothing,
  }) async {
    try {
      final bytes = await read();
      if (!mounted) return;
      if (bytes == null) {
        setState(() => _error = nothing ?? 'Could not read the picture.');
        return;
      }
      if (coverMimeType(bytes) == null) {
        setState(() => _error = 'The cover must be a JPG or PNG picture.');
        return;
      }
      if (bytes.length > maxCoverBytes) {
        setState(() => _error = 'The picture is too big (over 8 MB).');
        return;
      }
      setState(() {
        _newCover = bytes;
        _removeCover = false;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not read the picture: $e');
    }
  }

  // ---- saving ----

  /// A field counts as changed when its text is not what the files held (for
  /// several songs with different values, any text typed is a change).
  String? _changed(TextEditingController c, String before, bool same) {
    final t = c.text.trim();
    if (same && t == before) return null;
    if (!same && t.isEmpty) return null;
    return t;
  }

  Future<void> _save() async {
    final edit = TagEdit(
      title: _multi ? null : _changed(_title, _title0, _sameTitle),
      artist: _changed(_artist, _artist0, _sameArtist),
      album: _changed(_album, _album0, _sameAlbum),
      cover: _newCover,
      removeCover: _removeCover,
    );
    if (edit.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final failures = <String>[];
    var ok = 0;
    for (final p in _paths) {
      try {
        await writeTagValues(p, edit);
        await widget.library.reload(p);
        ok++;
      } on TagEditException catch (e) {
        failures.add('${fileNameOf(p)}: ${e.message}');
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _error =
          '${ok > 0 ? 'Saved $ok, but ' : ''}'
          '${failures.length} could not be changed:\n${failures.join('\n')}';
      if (ok > 0) {
        // What was saved is no longer a change to make again.
        _newCover = null;
        _removeCover = false;
      }
    });
  }

  // ---- view ----

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cover = _removeCover ? null : (_newCover ?? _currentCover);
    return AlertDialog(
      title: Text(_multi ? 'Edit info (${_paths.length} songs)' : 'Edit info'),
      content: SizedBox(
        width: 440,
        child: _paths.isEmpty
            ? const Text('These files cannot be edited.')
            : _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CoverBox(bytes: cover, multi: _multi, palette: p),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _chooseCover,
                                icon: const Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                ),
                                label: const Text('Choose picture…'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _pasteCover,
                                icon: const Icon(Icons.content_paste, size: 18),
                                label: const Text('Paste'),
                              ),
                              TextButton(
                                onPressed:
                                    _saving ||
                                        (cover == null && !_multi) ||
                                        _removeCover
                                    ? null
                                    : () => setState(() {
                                        _newCover = null;
                                        _removeCover = true;
                                      }),
                                child: Text(
                                  _multi ? 'Remove covers' : 'Remove cover',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_multi)
                      TextField(
                        controller: _title,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                    TextField(
                      controller: _artist,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText: 'Artist',
                        hintText: _sameArtist ? null : '(different)',
                      ),
                    ),
                    TextField(
                      controller: _album,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText: 'Album',
                        hintText: _sameAlbum ? null : '(different)',
                      ),
                    ),
                    if (_multi)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Only what you fill in changes; the rest stays as '
                          'each song has it.',
                          style: TextStyle(fontSize: 12, color: p.textDim),
                        ),
                      ),
                    if (_skipped > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '$_skipped file(s) skipped: their format '
                          '(${editableExtensions.join(', ')} only) cannot be '
                          'edited.',
                          style: TextStyle(fontSize: 12, color: p.textDim),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Saved into the song file itself.',
                        style: TextStyle(fontSize: 12, color: p.textDim),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loading || _paths.isEmpty ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

class _CoverBox extends StatelessWidget {
  const _CoverBox({
    required this.bytes,
    required this.multi,
    required this.palette,
  });

  final Uint8List? bytes;
  final bool multi;
  final NslPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: palette.hover,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes == null
          ? Icon(
              multi ? Icons.photo_library_outlined : Icons.music_note,
              color: palette.textDim,
              size: 32,
            )
          : Image.memory(
              bytes!,
              fit: BoxFit.cover,
              cacheWidth: 192,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.broken_image_outlined, color: palette.textDim),
            ),
    );
  }
}
