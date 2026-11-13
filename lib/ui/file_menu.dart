import 'package:flutter/material.dart';

import '../services/file_locator.dart';

/// The three "where is this file" commands, as menu entries.
enum FileCommand { showInFolder, copyPath, copyFile }

const fileCommandLabels = {
  FileCommand.showInFolder: 'Show in folder',
  FileCommand.copyPath: 'Copy path',
  FileCommand.copyFile: 'Copy file',
};

const fileCommandIcons = {
  FileCommand.showInFolder: Icons.folder_open,
  FileCommand.copyPath: Icons.link,
  FileCommand.copyFile: Icons.content_copy,
};

PopupMenuItem<String> _entry(FileCommand c) => PopupMenuItem<String>(
  value: 'file:${c.name}',
  child: Row(
    children: [
      Icon(fileCommandIcons[c], size: 18),
      const SizedBox(width: 10),
      Text(fileCommandLabels[c]!),
    ],
  ),
);

/// Menu entries for the [FileCommand]s, to put at the end of any
/// `PopupMenuButton`. Their values are `file:<name>`; check them with
/// [isFileCommand] and pass the chosen value to [runFileCommand].
List<PopupMenuEntry<String>> fileMenuItems({bool divider = true}) => [
  if (divider) const PopupMenuDivider(),
  for (final c in FileCommand.values) _entry(c),
];

/// True when a menu value came from [fileMenuItems].
bool isFileCommand(String value) => value.startsWith('file:');

/// Runs the command named by [value] on [path] and tells the user the result.
Future<void> runFileCommand(
  BuildContext context,
  String value,
  String path, {
  FileLocator? locator,
}) async {
  final l = locator ?? FileLocator.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final cmd = FileCommand.values.firstWhere(
    (c) => 'file:${c.name}' == value,
    orElse: () => FileCommand.showInFolder,
  );
  final r = switch (cmd) {
    FileCommand.showInFolder => await l.showInFolder(path),
    FileCommand.copyPath => await l.copyPath(path),
    FileCommand.copyFile => await l.copyFile(path),
  };
  // Opening Explorer needs no message; everything else says what happened.
  if (cmd == FileCommand.showInFolder && r.ok) return;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(r.message)));
}

/// Opens the file menu at [position] (a right-click on a tile or a card).
Future<void> showFileContextMenu(
  BuildContext context,
  Offset position,
  String path,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final value = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [for (final c in FileCommand.values) _entry(c)],
  );
  if (value != null && context.mounted) {
    await runFileCommand(context, value, path);
  }
}
