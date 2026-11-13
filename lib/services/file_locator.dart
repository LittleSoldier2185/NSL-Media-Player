import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

/// What happened when a file command ran; [message] is fit to show.
class LocateResult {
  const LocateResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// "Show in folder", "Copy path" and "Copy file" for any file in the app, so a
/// file can be found in File Explorer or handed to someone else.
///
/// The parts that touch the system are parameters so tests can replace them.
class FileLocator {
  FileLocator({
    Future<void> Function(List<String> args)? explorer,
    Future<void> Function(String text)? copyText,
    Future<bool> Function(List<String> files)? copyFiles,
    bool Function(String path)? fileExists,
    bool Function(String path)? dirExists,
  }) : _explorer = explorer ?? _runExplorer,
       _copyText = copyText ?? _setClipboard,
       _copyFiles = copyFiles ?? Pasteboard.writeFiles,
       _fileExists = fileExists ?? ((p) => File(p).existsSync()),
       _dirExists = dirExists ?? ((p) => Directory(p).existsSync());

  /// The one used by the app.
  static final instance = FileLocator();

  final Future<void> Function(List<String> args) _explorer;
  final Future<void> Function(String text) _copyText;
  final Future<bool> Function(List<String> files) _copyFiles;
  final bool Function(String path) _fileExists;
  final bool Function(String path) _dirExists;

  /// Starts explorer.exe through ShellExecute with the command line exactly as
  /// given: `Process.run` re-quotes arguments in a way Explorer misreads when
  /// the path has spaces or Thai letters, and it opens Documents instead.
  static Future<void> _runExplorer(List<String> args) async {
    final line = args.length == 2 && args[0] == '/select,'
        ? '/select,"${args[1]}"'
        : args.map((a) => '"$a"').join(' ');
    final shell = DynamicLibrary.open('shell32.dll');
    final shellExecute = shell
        .lookupFunction<
          IntPtr Function(
            IntPtr,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Int32,
          ),
          int Function(
            int,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<Utf16>,
            int,
          )
        >('ShellExecuteW');
    final verb = 'open'.toNativeUtf16();
    final exe = 'explorer.exe'.toNativeUtf16();
    final params = line.toNativeUtf16();
    try {
      shellExecute(0, verb, exe, params, nullptr, 1);
    } finally {
      calloc.free(verb);
      calloc.free(exe);
      calloc.free(params);
    }
  }

  static Future<void> _setClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// The folder that holds [path] (either kind of slash).
  static String parentOf(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }

  static String _native(String path) => path.replaceAll('/', '\\');

  /// Opens File Explorer with [path] selected. If the file is gone but its
  /// folder is still there, opens the folder instead.
  Future<LocateResult> showInFolder(String path) async {
    final native = _native(path);
    if (_fileExists(native)) {
      // Two arguments: Dart quotes only the path (`/select, "C:\a b\c.mp3"`),
      // which Explorer understands. Gluing them into one argument gets the
      // whole thing quoted when the path has spaces, and Explorer then opens
      // Documents instead.
      await _explorer(['/select,', native]);
      return const LocateResult(true, 'Showing it in File Explorer.');
    }
    final dir = parentOf(native);
    if (_dirExists(dir)) {
      await _explorer([dir]);
      return const LocateResult(
        false,
        'File not found. Opened its folder instead.',
      );
    }
    return const LocateResult(false, 'File not found.');
  }

  /// Puts the file's full path on the clipboard.
  Future<LocateResult> copyPath(String path) async {
    await _copyText(_native(path));
    return const LocateResult(true, 'Path copied.');
  }

  /// Puts the file itself on the clipboard, so Paste in a chat, an e-mail or
  /// File Explorer gives a copy of it.
  Future<LocateResult> copyFile(String path) async {
    final native = _native(path);
    if (!_fileExists(native)) {
      return const LocateResult(false, 'File not found.');
    }
    try {
      final ok = await _copyFiles([native]);
      return ok
          ? const LocateResult(true, 'File copied. Paste it where you want it.')
          : const LocateResult(false, 'Could not copy the file.');
    } on Object {
      return const LocateResult(false, 'Could not copy the file.');
    }
  }
}
