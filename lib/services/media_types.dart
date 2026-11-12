import 'dart:io';

const audioExtensions = {'mp3', 'flac', 'wav', 'm4a', 'ogg', 'aac'};
const videoExtensions = {'mp4', 'mkv', 'avi', 'mov', 'webm'};

/// Pictures the app can show (more, like HEIC, are added with the photo viewer).
const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
const pdfExtensions = {'pdf'};

/// What a file is. Only [audio] and [video] can be played; [image] and [pdf]
/// are opened in the photo viewer and the book reader.
enum MediaKind { audio, video, image, pdf }

/// The kind of [path] from its extension, or null for anything else.
MediaKind? kindOf(String path) {
  final e = extensionOf(path);
  if (audioExtensions.contains(e)) return MediaKind.audio;
  if (videoExtensions.contains(e)) return MediaKind.video;
  if (imageExtensions.contains(e)) return MediaKind.image;
  if (pdfExtensions.contains(e)) return MediaKind.pdf;
  return null;
}

/// True for any file the library keeps (music, video, pictures, PDF books).
bool isLibraryFile(String path) => kindOf(path) != null;

String extensionOf(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

/// True for a file the player can play (audio or video). Pictures and PDFs are
/// not "media" in this sense: they must never end up in the play queue.
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

String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

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
