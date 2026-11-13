import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/file_locator.dart';

void main() {
  late List<List<String>> explorerCalls;
  late List<String> copiedText;
  late List<List<String>> copiedFiles;

  FileLocator make({
    bool file = true,
    bool dir = true,
    bool copyOk = true,
    bool copyThrows = false,
  }) {
    explorerCalls = [];
    copiedText = [];
    copiedFiles = [];
    return FileLocator(
      explorer: (a) async => explorerCalls.add(a),
      copyText: (t) async => copiedText.add(t),
      copyFiles: (f) async {
        if (copyThrows) throw StateError('no clipboard');
        copiedFiles.add(f);
        return copyOk;
      },
      fileExists: (_) => file,
      dirExists: (_) => dir,
    );
  }

  test('Show in folder passes /select, and the path as separate args', () async {
    final l = make();
    final r = await l.showInFolder(r'C:\My Music\Album One\song a.mp3');
    expect(r.ok, isTrue);
    expect(explorerCalls, [
      ['/select,', r'C:\My Music\Album One\song a.mp3'],
    ]);
  });

  test('forward slashes are turned into backslashes for Explorer', () async {
    final l = make();
    await l.showInFolder('C:/Music/a.mp3');
    expect(explorerCalls.single, ['/select,', r'C:\Music\a.mp3']);
  });

  test('a missing file opens its folder and says so', () async {
    final l = make(file: false);
    final r = await l.showInFolder(r'C:\Music\gone.mp3');
    expect(r.ok, isFalse);
    expect(r.message, contains('not found'));
    expect(explorerCalls, [
      [r'C:\Music'],
    ]);
  });

  test('a missing file and folder opens nothing', () async {
    final l = make(file: false, dir: false);
    final r = await l.showInFolder(r'Z:\x\gone.mp3');
    expect(r.ok, isFalse);
    expect(explorerCalls, isEmpty);
  });

  test('Copy path copies the full path', () async {
    final l = make();
    final r = await l.copyPath('C:/Music/a b.mp3');
    expect(r.ok, isTrue);
    expect(copiedText, [r'C:\Music\a b.mp3']);
  });

  test('Copy file puts the file on the clipboard', () async {
    final l = make();
    final r = await l.copyFile(r'C:\Music\a.mp3');
    expect(r.ok, isTrue);
    expect(copiedFiles, [
      [r'C:\Music\a.mp3'],
    ]);
  });

  test('Copy file reports a missing file, a refusal and a crash', () async {
    expect(
      (await make(file: false).copyFile(r'C:\a.mp3')).message,
      contains('not found'),
    );
    expect((await make(copyOk: false).copyFile(r'C:\a.mp3')).ok, isFalse);
    expect((await make(copyThrows: true).copyFile(r'C:\a.mp3')).ok, isFalse);
  });

  test('parentOf works with either slash', () {
    expect(FileLocator.parentOf(r'C:\a\b.mp3'), r'C:\a');
    expect(FileLocator.parentOf('C:/a/b.mp3'), 'C:/a');
    expect(FileLocator.parentOf('b.mp3'), 'b.mp3');
  });
}
