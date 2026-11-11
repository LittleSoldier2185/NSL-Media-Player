import 'package:flutter/material.dart';

import '../services/playlist_service.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for a playlist name. Returns null if cancelled.
Future<String?> promptPlaylistName(
  BuildContext context, {
  String title = 'New playlist',
  String confirm = 'Create',
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = ctrl.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: submit, child: Text(confirm)),
        ],
      );
    },
  );
  // Not disposed here: the dialog's close animation still reads the controller.
}

/// Creates a playlist from [paths] after asking for its name.
Future<void> saveAsPlaylist(
  BuildContext context,
  PlaylistService playlists,
  List<String> paths, {
  String suggested = '',
}) async {
  if (paths.isEmpty) {
    _toast(context, 'Nothing to save.');
    return;
  }
  final name = await promptPlaylistName(
    context,
    title: 'Save as playlist',
    confirm: 'Save',
    initial: suggested,
  );
  if (name == null || !context.mounted) return;
  final pl = playlists.create(name, paths);
  _toast(context, 'Saved "${pl.name}" with ${pl.paths.length} files.');
}

/// Lets the user pick an existing playlist (or create one) and adds [paths].
Future<void> addToPlaylist(
  BuildContext context,
  PlaylistService playlists,
  List<String> paths,
) async {
  if (paths.isEmpty) return;
  const create = '__new__';
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(
        paths.length == 1
            ? 'Add to playlist'
            : 'Add ${paths.length} files to playlist',
      ),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, create),
          child: const Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 12),
              Text('New playlist…'),
            ],
          ),
        ),
        if (playlists.all.isNotEmpty) const Divider(height: 1),
        for (final p in playlists.all)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p.id),
            child: Row(
              children: [
                const Icon(Icons.queue_music, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                Text(
                  '${p.paths.length}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == create) {
    final name = await promptPlaylistName(context);
    if (name == null || !context.mounted) return;
    final pl = playlists.create(name, paths);
    _toast(context, 'Created "${pl.name}" with ${pl.paths.length} files.');
    return;
  }
  final pl = playlists.byId(choice);
  if (pl == null) return;
  final added = playlists.addPaths(choice, paths);
  final skipped = paths.length - added;
  _toast(
    context,
    added == 0
        ? 'Already in "${pl.name}".'
        : skipped == 0
        ? 'Added $added to "${pl.name}".'
        : 'Added $added to "${pl.name}" ($skipped already there).',
  );
}
