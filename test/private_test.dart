import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/library_service.dart';
import 'package:nsl_media_player/services/private_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nsl_private_test');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => tmp.delete(recursive: true));

  var clock = DateTime(2026, 1, 1, 12);
  PrivateService make({File? file}) => PrivateService(
    file: file ?? File('${tmp.path}\\private.json'),
    iterations: 10,
    now: () => clock,
    idleTimer: false,
  );

  setUp(() => clock = DateTime(2026, 1, 1, 12));

  group('PrivateService PIN', () {
    test('starts without a PIN and locked', () {
      final s = make();
      expect(s.hasPin, isFalse);
      expect(s.unlocked, isFalse);
      s.dispose();
    });

    test('a short PIN is refused; a good one opens Private', () async {
      final s = make();
      expect(await s.setPin('12'), isFalse);
      expect(s.hasPin, isFalse);
      expect(await s.setPin('1234'), isTrue);
      expect(s.hasPin, isTrue);
      expect(s.unlocked, isTrue);
      s.dispose();
    });

    test('the PIN is not stored, and is checked after a restart', () async {
      final f = File('${tmp.path}\\private.json');
      final s = make(file: f);
      await s.setPin('hunter22');
      s.dispose();
      expect(f.readAsStringSync().contains('hunter22'), isFalse);

      final again = make(file: f);
      expect(again.hasPin, isTrue);
      expect(again.unlocked, isFalse, reason: 'always starts locked');
      expect(await again.unlock('wrong'), isFalse);
      expect(await again.unlock('hunter22'), isTrue);
      expect(again.unlocked, isTrue);
      again.dispose();
    });

    test('a first PIN cannot replace an existing one', () async {
      final s = make();
      await s.setPin('1234');
      expect(await s.setPin('9999'), isFalse);
      s.lock();
      expect(await s.unlock('1234'), isTrue);
      s.dispose();
    });

    test('changing the PIN needs the old one', () async {
      final s = make();
      await s.setPin('1234');
      expect(await s.changePin('0000', 'abcd'), isFalse);
      expect(await s.changePin('1234', 'abcd'), isTrue);
      s.lock();
      expect(await s.unlock('1234'), isFalse);
      expect(await s.unlock('abcd'), isTrue);
      s.dispose();
    });

    test('same PIN gives a different hash (random salt)', () async {
      final a = File('${tmp.path}\\a.json'), b = File('${tmp.path}\\b.json');
      await (make(file: a)).setPin('1234');
      await (make(file: b)).setPin('1234');
      expect(a.readAsStringSync(), isNot(b.readAsStringSync()));
    });

    test('PBKDF2 matches a known test vector', () {
      // RFC 6070 style vector for HMAC-SHA256: P="password", S="salt", c=1.
      final out = PrivateService.pbkdf2('password', 'salt'.codeUnits, 1);
      final hex = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });
  });

  group('PrivateService wrong tries', () {
    test('five free tries, then waiting that survives a restart', () async {
      final f = File('${tmp.path}\\private.json');
      final s = make(file: f);
      await s.setPin('1234');
      s.lock();
      for (var i = 0; i < PrivateService.freeTries - 1; i++) {
        expect(await s.unlock('bad'), isFalse);
        expect(s.waitLeft, isNull);
      }
      expect(await s.unlock('bad'), isFalse);
      expect(s.waitLeft, isNotNull);
      // While waiting even the right PIN is not tried.
      expect(await s.unlock('1234'), isFalse);
      s.dispose();

      final again = make(file: f);
      expect(again.waitLeft, isNotNull);
      clock = clock.add(const Duration(minutes: 1));
      expect(again.waitLeft, isNull);
      expect(await again.unlock('1234'), isTrue);
      again.dispose();
    });

    test('the wait grows but is capped', () async {
      final s = make();
      await s.setPin('1234');
      s.lock();
      for (var i = 0; i < 30; i++) {
        clock = clock.add(const Duration(hours: 1));
        await s.unlock('bad');
      }
      expect(s.waitLeft! <= PrivateService.maxWait, isTrue);
      s.dispose();
    });
  });

  group('PrivateService locking', () {
    test('idle time locks, activity postpones it', () async {
      final s = make();
      await s.setPin('1234');
      s.autoLockMinutes = 5;
      clock = clock.add(const Duration(minutes: 4));
      s.activity();
      clock = clock.add(const Duration(minutes: 4));
      s.checkIdle();
      expect(s.unlocked, isTrue);
      clock = clock.add(const Duration(minutes: 2));
      s.checkIdle();
      expect(s.unlocked, isFalse);
      s.dispose();
    });

    test('idle lock off never locks', () async {
      final s = make();
      await s.setPin('1234');
      s.autoLockMinutes = 0;
      clock = clock.add(const Duration(days: 2));
      s.checkIdle();
      expect(s.unlocked, isTrue);
      s.dispose();
    });

    test('minimizing locks only when that is on', () async {
      final s = make();
      await s.setPin('1234');
      s.lockOnMinimize = false;
      s.windowMinimized();
      expect(s.unlocked, isTrue);
      s.lockOnMinimize = true;
      s.windowMinimized();
      expect(s.unlocked, isFalse);
      s.dispose();
    });

    test('locking tells the app so it can stop playing', () async {
      final s = make();
      var calls = 0;
      s.onLocked = () => calls++;
      await s.setPin('1234');
      s.lock();
      s.lock(); // already locked
      expect(calls, 1);
      s.dispose();
    });

    test('settings are remembered', () async {
      final f = File('${tmp.path}\\private.json');
      final s = make(file: f);
      await s.setPin('1234');
      s.autoLockMinutes = 30;
      s.hideEntry = true;
      s.maskTitles = false;
      s.lockOnMinimize = false;
      s.dispose();
      final again = make(file: f);
      expect(again.autoLockMinutes, 30);
      expect(again.hideEntry, isTrue);
      expect(again.maskTitles, isFalse);
      expect(again.lockOnMinimize, isFalse);
      again.dispose();
    });
  });

  group('what counts as private', () {
    test('tagged files and private folders, without regard to case', () async {
      final s = make();
      await s.setPin('1234');
      s.folders = () => ['D:\\Secret'];
      s.addFiles(['C:\\Music\\Song.mp3']);
      expect(s.isPrivate('c:\\music\\song.MP3'), isTrue);
      expect(s.isPrivate('D:\\secret\\sub\\a.jpg'), isTrue);
      expect(s.isPrivate('D:\\Secret2\\a.jpg'), isFalse);
      expect(s.isPrivate('C:\\Music\\Other.mp3'), isFalse);
      expect(s.isPrivate(null), isFalse);
      s.removeFiles(['C:\\MUSIC\\song.mp3']);
      expect(s.isPrivate('C:\\Music\\Song.mp3'), isFalse);
      s.dispose();
    });

    test('files stay private while locked, and after a restart', () async {
      final f = File('${tmp.path}\\private.json');
      final s = make(file: f);
      await s.setPin('1234');
      s.addFiles(['C:\\a.mp3']);
      s.lock();
      expect(s.isPrivate('C:\\a.mp3'), isTrue);
      s.dispose();
      final again = make(file: f);
      expect(again.isPrivate('C:\\a.mp3'), isTrue);
      again.dispose();
    });

    test('reset forgets the PIN and the tags, and locks', () async {
      final s = make();
      var locked = 0;
      s.onLocked = () => locked++;
      await s.setPin('1234');
      s.addFiles(['C:\\a.mp3']);
      s.resetAll();
      expect(s.hasPin, isFalse);
      expect(s.unlocked, isFalse);
      expect(s.isPrivate('C:\\a.mp3'), isFalse);
      expect(locked, 1);
      expect(await s.setPin('5678'), isTrue);
      s.dispose();
    });
  });

  group('library and Private', () {
    test('the normal library leaves out private files; the private one '
        'lists the tagged files', () async {
      final music = Directory('${tmp.path}\\music')..createSync();
      final secret = File('${music.path}\\secret.mp3')..writeAsBytesSync([1]);
      File('${music.path}\\open.mp3').writeAsBytesSync([1]);
      final prefs = await SharedPreferences.getInstance();

      final lock = make();
      await lock.setPin('1234');
      lock.addFiles([secret.path]);

      final normal = LibraryService(
        prefs,
        indexFile: File('${tmp.path}\\library.json'),
        autoRescan: false,
        excluded: lock.isPrivate,
      );
      await normal.addFolder(music.path);
      expect(normal.items.map((i) => i.title), isNot(contains('secret')));
      expect(normal.items.length, 1);

      final priv = LibraryService(
        prefs,
        indexFile: File('${tmp.path}\\private_index.json'),
        autoRescan: false,
        foldersKey: 'privateFolders',
        extraFiles: () => lock.taggedFiles,
      );
      await priv.scan();
      expect(priv.items.map((i) => i.path), [secret.path]);
      // The two libraries keep different folder lists.
      expect(priv.folders, isEmpty);
      expect(normal.folders, [music.path]);

      // Taking the file out of Private puts it back in the normal library.
      lock.removeFiles([secret.path]);
      await normal.scan();
      await priv.scan();
      expect(normal.items.length, 2);
      expect(priv.items, isEmpty);
      lock.dispose();
    });

    test('a private folder inside a normal one is skipped, then returned '
        'when it stops being private', () async {
      final music = Directory('${tmp.path}\\music')..createSync();
      final hidden = Directory('${music.path}\\hidden')..createSync();
      File('${hidden.path}\\h.mp3').writeAsBytesSync([1]);
      File('${music.path}\\a.mp3').writeAsBytesSync([1]);
      final prefs = await SharedPreferences.getInstance();

      final lock = make();
      await lock.setPin('1234');
      lock.folders = () => [hidden.path];
      final normal = LibraryService(
        prefs,
        indexFile: File('${tmp.path}\\library.json'),
        autoRescan: false,
        excluded: lock.isPrivate,
      );
      await normal.addFolder(music.path);
      expect(normal.items.length, 1);

      lock.folders = () => const [];
      await normal.scan();
      expect(normal.items.length, 2);
      lock.dispose();
    });

    test('private files do not reach the normal index file', () async {
      final music = Directory('${tmp.path}\\music')..createSync();
      final secret = File('${music.path}\\secret.mp3')..writeAsBytesSync([1]);
      final prefs = await SharedPreferences.getInstance();
      final lock = make();
      await lock.setPin('1234');
      lock.addFiles([secret.path]);
      final index = File('${tmp.path}\\library.json');
      final normal = LibraryService(
        prefs,
        indexFile: index,
        autoRescan: false,
        excluded: lock.isPrivate,
      );
      await normal.addFolder(music.path);
      expect(index.readAsStringSync().contains('secret'), isFalse);
      lock.dispose();
    });
  });
}
