import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/library_service.dart';
import 'photo_viewer.dart';
import 'theme.dart';

/// Pictures of one day, newest day first.
class PhotoDay {
  PhotoDay(this.day, this.items);
  final DateTime day;
  final List<LibraryItem> items;
}

/// Groups [items] by the day they were taken (or changed), newest first.
List<PhotoDay> groupByDay(Iterable<LibraryItem> items) {
  final sorted = items.toList()..sort((a, b) => b.when.compareTo(a.when));
  final out = <PhotoDay>[];
  for (final i in sorted) {
    final t = DateTime.fromMillisecondsSinceEpoch(i.when);
    final day = DateTime(t.year, t.month, t.day);
    if (out.isEmpty || out.last.day != day) {
      out.add(PhotoDay(day, []));
    }
    out.last.items.add(i);
  }
  return out;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Today", "Yesterday" or e.g. "Sat 8 Nov 2026".
String dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]} '
      '${day.year}';
}

/// Photos: every picture of the library folders on a timeline, a day at a
/// time. Click one to open the viewer.
class PhotosView extends StatefulWidget {
  const PhotosView({
    super.key,
    required this.library,
    required this.onOpenLibrary,
    this.now,
  });

  final LibraryService library;
  final VoidCallback onOpenLibrary;

  /// "Today" (tests).
  final DateTime Function()? now;

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  final _search = TextEditingController();
  double _tile = 150;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LibraryItem> _filtered() {
    final q = _search.text.trim().toLowerCase();
    final all = widget.library.images;
    if (q.isEmpty) return all;
    return [
      for (final i in all)
        if (i.title.toLowerCase().contains(q) ||
            i.path.toLowerCase().contains(q))
          i,
    ];
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) await widget.library.addFolder(dir);
  }

  void _open(List<LibraryItem> list, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerPage(items: list, index: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final lib = widget.library;
        final list = _filtered();
        final days = groupByDay(list);
        final now = (widget.now ?? DateTime.now)();
        final dpr = MediaQuery.devicePixelRatioOf(context);
        // Position of each picture in [list], to open the viewer on it.
        final indexOf = {for (var i = 0; i < list.length; i++) list[i].path: i};
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Photos',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (lib.imageCount > 0)
                    Text(
                      '${lib.imageCount}',
                      style: TextStyle(fontSize: 14, color: p.textDim),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: 220,
                    height: 36,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search photos',
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
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.photo_size_select_large, size: 16, color: p.icon),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: _tile,
                      min: 90,
                      max: 260,
                      onChanged: (v) => setState(() => _tile = v),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add folder'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: lib.scanning && list.isEmpty
                    ? _Message('Looking through your library folders…', p: p)
                    : list.isEmpty
                    ? _empty(p)
                    : CustomScrollView(
                        slivers: [
                          for (final d in days) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      dayLabel(d.day, now),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: p.text,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      d.items.length == 1
                                          ? '1 photo'
                                          : '${d.items.length} photos',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: p.textDim,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.only(bottom: 18),
                              sliver: SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: _tile,
                                      mainAxisSpacing: 6,
                                      crossAxisSpacing: 6,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  i,
                                ) {
                                  final item = d.items[i];
                                  return _Tile(
                                    item: item,
                                    cacheWidth: (_tile * dpr).round().clamp(
                                      128,
                                      600,
                                    ),
                                    onTap: () =>
                                        _open(list, indexOf[item.path]!),
                                  );
                                }, childCount: d.items.length),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(NslPalette p) {
    final lib = widget.library;
    if (_search.text.trim().isNotEmpty) {
      return _Message('No photo matches "${_search.text.trim()}".', p: p);
    }
    if (lib.folders.isEmpty) {
      return _Message(
        'Add a folder with pictures and your photos will show up here.',
        p: p,
      );
    }
    return _Message('No pictures found in your library folders.', p: p);
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {required this.p});
  final String text;
  final NslPalette p;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_library_outlined, size: 48, color: p.textDim),
        const SizedBox(height: 14),
        Text(text, style: TextStyle(fontSize: 14, color: p.textDim)),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.cacheWidth,
    required this.onTap,
  });

  final LibraryItem item;
  final int cacheWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: item.title,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ColoredBox(
              color: p.track,
              child: Image.file(
                File(item.path),
                fit: BoxFit.cover,
                cacheWidth: cacheWidth,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  size: 22,
                  color: p.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
