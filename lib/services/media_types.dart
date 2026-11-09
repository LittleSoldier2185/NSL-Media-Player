import 'dart:io';

const audioExtensions = {'mp3', 'flac', 'wav', 'm4a', 'ogg', 'aac'};
const videoExtensions = {'mp4', 'mkv', 'avi', 'mov', 'webm'};

String extensionOf(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

bool isSupportedMedia(String path) {
  final e = extensionOf(path);
  return audioExtensions.contains(e) || videoExtensions.contains(e);
}

/// Returns the first supported media path in [args], or null.
String? firstMediaArg(Iterable<String> args) {
  for (final a in args) {
    if (isSupportedMedia(a)) return a;
  }
  return null;
}

String fileNameOf(String path) => path.split(RegExp(r'[\/]')).last;

/// Supported media files in [dir] (recursive), sorted by path.
List<String> mediaInFolder(String dir) {
  final out = <String>[];
  try {
    for (final e in Directory(
      dir,
    ).listSync(recursive: true, followLinks: false)) {
      if (e is File && isSupportedMedia(e.path)) out.add(e.path);
    }
  } on FileSystemException {
    // unreadable folder: return what we have
  }
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}
