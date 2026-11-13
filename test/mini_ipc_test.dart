import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/mini_ipc.dart';
import 'package:nsl_media_player/services/mini_session_tracker.dart';

class FakePort implements MiniHostPort {
  final Json snapshot = {
    'queue': ['a.mp3', 'b.mp4'],
    'index': 1,
    'posMs': 5000,
    'playing': true,
    'volume': 80.0,
    'speed': 1.0,
  };
  final calls = <String>[];
  Json? adopted;
  bool? adoptPlay;
  Json? prefs;
  List<Json>? history;
  Json? resumed;

  @override
  Json pauseAndSnapshot() {
    calls.add('pause');
    return snapshot;
  }

  @override
  Future<void> adopt(Json state, {required bool play}) async {
    calls.add('adopt');
    adopted = state;
    adoptPlay = play;
  }

  @override
  void applyPrefs(Json p) {
    calls.add('prefs');
    prefs = p;
  }

  @override
  void recordHistory(List<Json> entries) {
    calls.add('history');
    history = entries;
  }

  @override
  void bringToFront() => calls.add('front');

  @override
  void resumeLocal(Json s) {
    calls.add('resume');
    resumed = s;
  }
}

/// A "mini process" that is really just a MiniChild in this test process.
class FakeMini {
  MiniChild? child;
  final exit = Completer<int>();
  final connected = Completer<void>();
  final received = <Json>[];
  var killed = false;

  Future<MiniProcess> spawn(List<String> args, {String? token}) async {
    final parsed = parseMiniArgs(args)!;
    final useArgs = MiniArgs(
      port: parsed.port,
      token: token ?? parsed.token,
      origin: parsed.origin,
    );
    unawaited(
      MiniChild.connect(useArgs, timeout: const Duration(seconds: 2)).then((c) {
        child = c;
        if (!connected.isCompleted) connected.complete();
        c?.commands.listen(received.add);
      }),
    );
    return MiniProcess(exit.future, () {
      killed = true;
      if (!exit.isCompleted) exit.complete(-1);
    });
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late FakePort port;
  late FakeMini mini;
  late MiniHost host;

  /// Launches and waits until the (fake) mini process has its `init`.
  Future<bool> open([Offset? origin]) async {
    final ok = await host.launch(origin: origin);
    if (ok) await mini.connected.future;
    return ok;
  }

  setUp(() {
    port = FakePort();
    mini = FakeMini();
    host = MiniHost(
      port,
      spawner: mini.spawn,
      connectTimeout: const Duration(seconds: 3),
    );
  });
  tearDown(() => host.dispose());

  group('parseMiniArgs', () {
    test('reads port, token and position', () {
      final a = parseMiniArgs([
        '--mini',
        '--port=1234',
        '--token=abc',
        '--pos=10.5,20',
      ])!;
      expect(a.port, 1234);
      expect(a.token, 'abc');
      expect(a.origin, const Offset(10.5, 20));
    });

    test('position is optional', () {
      expect(
        parseMiniArgs(['--mini', '--port=1', '--token=t'])!.origin,
        isNull,
      );
    });

    test('not a mini launch, or incomplete', () {
      expect(parseMiniArgs(['C:\\a.mp3']), isNull);
      expect(parseMiniArgs(['--mini']), isNull);
      expect(parseMiniArgs(['--mini', '--port=x', '--token=t']), isNull);
      expect(parseMiniArgs(['--mini', '--port=1']), isNull);
    });
  });

  group('handover', () {
    test(
      'child receives what to play; main pauses and goes inactive-free',
      () async {
        expect(await open(const Offset(5, 6)), isTrue);
        expect(host.active, isTrue);
        expect(port.calls, ['pause']);
        expect(mini.child, isNotNull);
        expect(mini.child!.init['queue'], ['a.mp3', 'b.mp4']);
        expect(mini.child!.init['index'], 1);
        expect(mini.child!.init['posMs'], 5000);
        expect(mini.child!.init['playing'], true);
        expect(mini.child!.origin, const Offset(5, 6));
      },
    );

    test('a second launch while open does not start another', () async {
      await open();
      var spawned = 0;
      final again = MiniHost(
        port,
        spawner: (a) {
          spawned++;
          return mini.spawn(a);
        },
      );
      await again.launch();
      await again.launch();
      expect(spawned, 1);
      again.dispose();
    });

    test('forwarded commands reach the mini player', () async {
      await open();
      await host.open(['x.mp4'], start: 0, at: const Duration(seconds: 9));
      await host.add(['y.mp3']);
      host.toggle();
      host.next();
      host.previous();
      host.bringBack();
      await settle();
      expect(mini.received.map((m) => m['cmd']), [
        'open',
        'add',
        'toggle',
        'next',
        'prev',
        'return',
      ]);
      expect(mini.received[0]['paths'], ['x.mp4']);
      expect(mini.received[0]['posMs'], 9000);
      expect(mini.received[1]['paths'], ['y.mp3']);
    });
  });

  group('coming back', () {
    Future<void> finish(String evt, {bool playing = true}) async {
      await mini.child!.finish(
        evt,
        state: {
          'queue': ['a.mp3', 'b.mp4'],
          'index': 1,
          'posMs': 42000,
          'playing': playing,
        },
        prefs: {
          'miniScale': 1.5,
          'miniPos': ['3', '4'],
          'evil': 'x',
        },
        history: [
          {
            'path': 'b.mp4',
            'seconds': 37.0,
            'posMs': 42000,
            'durMs': 90000,
            'plays': 0,
          },
        ],
      );
      await settle();
    }

    test('expand: state adopted and playing, window brought forward', () async {
      await open();
      await finish('expand');
      expect(host.active, isFalse);
      expect(host.lastReturn, MiniReturn.expand);
      expect(port.adopted!['posMs'], 42000);
      expect(port.adoptPlay, isTrue);
      expect(
        port.calls,
        containsAllInOrder(['pause', 'prefs', 'history', 'adopt', 'front']),
      );
    });

    test('expand while the mini player was paused stays paused', () async {
      await open();
      await finish('expand', playing: false);
      expect(port.adoptPlay, isFalse);
    });

    test('close: state adopted but paused, no bring-to-front', () async {
      await open();
      await finish('close');
      expect(host.lastReturn, MiniReturn.close);
      expect(port.adoptPlay, isFalse);
      expect(port.calls, isNot(contains('front')));
    });

    test('only known preferences are applied', () async {
      await open();
      await finish('expand');
      expect(port.prefs, {
        'miniScale': 1.5,
        'miniPos': ['3', '4'],
      });
    });

    test('history entries are passed on', () async {
      await open();
      await finish('close');
      expect(port.history!.single['path'], 'b.mp4');
      expect(port.history!.single['seconds'], 37.0);
    });

    test(
      'inactive before adopting, so playback is not forwarded back',
      () async {
        var activeDuringAdopt = true;
        final p = _SpyPort(onAdopt: () => activeDuringAdopt = host.active);
        final h = MiniHost(p, spawner: mini.spawn);
        await h.launch();
        await mini.connected.future;
        await mini.child!.finish(
          'expand',
          state: {
            'queue': ['a'],
            'playing': true,
          },
        );
        await settle();
        expect(activeDuringAdopt, isFalse);
        h.dispose();
      },
    );

    test('a gone mini player (crash) just ends the session', () async {
      await open();
      mini.exit.complete(1);
      await settle();
      expect(host.active, isFalse);
      expect(port.adopted, isNull);
    });
  });

  group('failures', () {
    test('a peer with the wrong token is rejected; launch gives up', () async {
      final h = MiniHost(
        port,
        spawner: (a) => mini.spawn(a, token: 'wrong'),
        connectTimeout: const Duration(milliseconds: 400),
      );
      expect(await h.launch(), isFalse);
      expect(h.active, isFalse);
      expect(port.calls, contains('resume'));
      expect(port.resumed!['index'], 1);
      expect(mini.killed, isTrue);
      h.dispose();
    });

    test('a spawner that throws leaves the main window playing', () async {
      final h = MiniHost(
        port,
        spawner: (_) async => throw StateError('no exe'),
      );
      expect(await h.launch(), isFalse);
      expect(h.active, isFalse);
      expect(port.calls, containsAllInOrder(['pause', 'resume']));
      h.dispose();
    });

    test('child cannot connect when nothing is listening', () async {
      final c = await MiniChild.connect(
        const MiniArgs(port: 1, token: 't'),
        timeout: const Duration(milliseconds: 300),
      );
      expect(c, isNull);
    });

    test('finish reports false once the main window is gone', () async {
      await open();
      final child = mini.child!;
      host.dispose(); // main window closes
      await settle();
      expect(child.mainAlive, isFalse);
      expect(await child.finish('expand', state: {}), isFalse);
    });
  });

  group('MiniSessionTracker', () {
    late DateTime clock;
    late MiniSessionTracker t;
    setUp(() {
      clock = DateTime(2026, 1, 1, 12);
      t = MiniSessionTracker(now: () => clock);
    });
    void advance(int s) => clock = clock.add(Duration(seconds: s));

    test('counts only the time spent playing', () {
      t.trackChanged('a.mp4', countPlay: false);
      t.playingChanged(true);
      advance(10);
      t.playingChanged(false);
      advance(100); // paused
      t.playingChanged(true);
      advance(5);
      final r = t.results().single;
      expect(r['seconds'], closeTo(15, 0.001));
      expect(r['plays'], 0);
    });

    test('tracks each file separately and counts new plays', () {
      t.trackChanged('a.mp4', countPlay: false);
      t.playingChanged(true);
      advance(4);
      t.progress(4000, 60000);
      t.trackChanged('b.mp3');
      advance(6);
      t.progress(6000, 200000);
      final r = t.results();
      expect(r.map((e) => e['path']), ['a.mp4', 'b.mp3']);
      expect(r[0]['seconds'], closeTo(4, 0.001));
      expect(r[0]['posMs'], 4000);
      expect(r[1]['seconds'], closeTo(6, 0.001));
      expect(r[1]['plays'], 1);
      expect(r[1]['durMs'], 200000);
    });

    test('results can be read more than once without double counting', () {
      t.trackChanged('a.mp4', countPlay: false);
      t.playingChanged(true);
      advance(3);
      expect(t.results().single['seconds'], closeTo(3, 0.001));
      advance(2);
      expect(t.results().single['seconds'], closeTo(5, 0.001));
    });

    test('nothing played, nothing reported', () {
      t.trackChanged('a.mp4', countPlay: false);
      expect(t.results(), isEmpty);
    });
  });

  group('closing for Private', () {
    bool isPrivate(String p) => p.startsWith('priv');

    test(
      'a mini player holding a private file is closed, not handed back',
      () async {
        port.snapshot['queue'] = ['a.mp3', 'priv1.mp4'];
        await open();
        expect(host.closeIfHolds(isPrivate), isTrue);
        await settle();
        expect(host.active, isFalse);
        expect(mini.killed, isTrue);
        expect(host.lastReturn, MiniReturn.close);
        // Its queue is thrown away: nothing is adopted or recorded.
        expect(port.calls, isNot(contains('adopt')));
        expect(port.calls, isNot(contains('history')));
      },
    );

    test('a private file opened in it later counts too', () async {
      await open();
      expect(host.closeIfHolds(isPrivate), isFalse);
      await host.open(['priv2.mp3']);
      expect(host.closeIfHolds(isPrivate), isTrue);
      expect(host.active, isFalse);
    });

    test('a private file added to it counts', () async {
      await open();
      await host.add(['priv3.mp3']);
      expect(host.closeIfHolds(isPrivate), isTrue);
    });

    test('a mini player with only ordinary files is left playing', () async {
      await open();
      expect(host.closeIfHolds(isPrivate), isFalse);
      expect(host.active, isTrue);
      expect(mini.killed, isFalse);
    });

    test('nothing to close when no mini player is open', () {
      expect(host.closeIfHolds(isPrivate), isFalse);
    });
  });
}

class _SpyPort extends FakePort {
  _SpyPort({required this.onAdopt});
  final void Function() onAdopt;

  @override
  Future<void> adopt(Json state, {required bool play}) async {
    onAdopt();
    return super.adopt(state, play: play);
  }
}
