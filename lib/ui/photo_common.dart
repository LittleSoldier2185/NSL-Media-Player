import 'package:flutter/material.dart';

import '../services/library_service.dart';
import '../services/playlist_service.dart';

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

/// The pictures of one folder: every folder with pictures is an album.
class PhotoFolder {
  PhotoFolder(this.dir, this.items);

  /// Full folder path.
  final String dir;

  /// Newest first.
  final List<LibraryItem> items;

  String get name => LibraryService.folderName(dir);
  int get newest => items.first.when;
}

String _parentOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? '' : path.substring(0, i);
}

/// Folder albums, the one with the newest picture first. Folder names that
/// differ only by case are the same folder (Windows paths).
List<PhotoFolder> folderAlbums(Iterable<LibraryItem> images) {
  final groups = <String, PhotoFolder>{};
  for (final i in images) {
    final dir = _parentOf(i.path);
    groups
        .putIfAbsent(dir.toLowerCase(), () => PhotoFolder(dir, []))
        .items
        .add(i);
  }
  final out = groups.values.toList();
  for (final f in out) {
    f.items.sort((a, b) => b.when.compareTo(a.when));
  }
  out.sort((a, b) => b.newest.compareTo(a.newest));
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

/// Asks for a name; null when cancelled.
Future<String?> askAlbumName(
  BuildContext context, {
  String title = 'New album',
  String initial = '',
  String action = 'Create',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial, action: action),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
  });

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  // Owned by the dialog, so it lives exactly as long as the field does
  // (including the closing animation).
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'Album name'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _c.text),
        child: Text(widget.action),
      ),
    ],
  );
}

/// A menu that puts pictures into an album you pick, or into a new one.
class AddToAlbumButton extends StatelessWidget {
  const AddToAlbumButton({
    super.key,
    required this.albums,
    required this.paths,
    required this.child,
    this.tooltip = 'Add to album',
    this.onDone,
  });

  final PlaylistService albums;

  /// The pictures to add, read when a choice is made.
  final List<String> Function() paths;
  final Widget child;
  final String tooltip;

  /// Called after pictures were added (to leave selection mode, for example).
  final VoidCallback? onDone;

  static const _new = '__new__';

  Future<void> _chosen(BuildContext context, String id) async {
    final list = paths();
    if (list.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    String message;
    if (id == _new) {
      final name = await askAlbumName(context);
      if (name == null) return;
      final a = albums.create(name, list);
      message = 'Added ${list.length} to "${a.name}"';
    } else {
      final a = albums.byId(id);
      if (a == null) return;
      final n = albums.addPaths(id, list);
      message = n == 0 ? 'Already in "${a.name}"' : 'Added $n to "${a.name}"';
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
    onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: albums,
      builder: (context, _) => PopupMenuButton<String>(
        tooltip: tooltip,
        onSelected: (id) => _chosen(context, id),
        itemBuilder: (_) => [
          for (final a in albums.all)
            PopupMenuItem(
              value: a.id,
              child: Text('${a.name}  ·  ${a.paths.length}'),
            ),
          if (albums.all.isNotEmpty) const PopupMenuDivider(),
          const PopupMenuItem(value: _new, child: Text('New album…')),
        ],
        child: child,
      ),
    );
  }
}
