import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Talking between the main window and a separate mini player process.
///
/// Pressing "Mini player" starts a second copy of the app with `--mini`. The
/// two talk over a loopback socket, one JSON message per line:
///
/// main -> mini
///   `{cmd: init, queue, index, posMs, playing, volume, speed}`  what to play
///   `{cmd: open, paths, start, posMs?}` / `{cmd: add, paths}`    forwarded
///   `{cmd: toggle | next | prev}`                               forwarded
///   `{cmd: return}`                                             bring it back
/// mini -> main
///   `{evt: hello, token}`                                       handshake
///   `{evt: expand | close, state, prefs, history}`              mini is done
///
/// The mini process is the only one playing while it is open; the main window
/// stays usable for browsing and forwards "play this" to it.
typedef Json = Map<String, dynamic>;

/// Preferences the mini process may hand back (size, position, volume...).
/// The main process owns the preferences file, so it applies these itself.
const miniPrefKeys = [
  'miniScale',
  'miniCardWidth',
  'miniPos',
  'miniOpacity',
  'miniOnTop',
  'volume',
];

/// What the host needs from the main window.
abstract class MiniHostPort {
  /// Pauses local playback and returns what the mini player should continue:
  /// `queue`, `index`, `posMs`, `playing`, `volume`, `speed`.
  Json pauseAndSnapshot();

  /// Continues playback locally with the state the mini player ended with.
  Future<void> adopt(Json state, {required bool play});

  /// Applies preferences changed in the mini process (already filtered).
  void applyPrefs(Json prefs);

  /// Adds what was watched in the mini player to the history.
  void recordHistory(List<Json> entries);

  void bringToFront();

  /// The mini player could not be started: carry on in the main window.
  void resumeLocal(Json snapshot);
}

/// Playback commands the controller forwards while a mini player is open.
abstract class RemotePlayback {
  bool get active;
  Future<void> open(List<String> paths, {int start = 0, Duration? at});
  Future<void> add(List<String> paths);
  void toggle();
  void next();
  void previous();
}

class MiniProcess {
  MiniProcess(this.exitCode, this.kill);
  final Future<int> exitCode;
  final void Function() kill;
}

typedef MiniSpawner = Future<MiniProcess> Function(List<String> args);

/// Starts another copy of this app.
Future<MiniProcess> spawnSelf(List<String> args) async {
  final p = await Process.start(Platform.resolvedExecutable, args);
  // Unread pipes could fill up and block the child.
  unawaited(p.stdout.drain<void>());
  unawaited(p.stderr.drain<void>());
  return MiniProcess(p.exitCode, () => p.kill());
}

// ---- line-based JSON channel ----

class _Channel {
  _Channel(this.socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            try {
              final m = jsonDecode(line);
              if (m is Map<String, dynamic>) _messages.add(m);
            } on FormatException {
              // ignore garbage
            }
          },
          onDone: _done,
          onError: (Object _) => _done(),
        );
  }

  final Socket socket;
  late final StreamSubscription<String> _sub;
  final _messages = StreamController<Json>.broadcast();
  final _closed = Completer<void>();

  Stream<Json> get messages => _messages.stream;
  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  void _done() {
    if (!_closed.isCompleted) _closed.complete();
    _messages.close();
  }

  void send(Json m) {
    if (isClosed) return;
    try {
      socket.write('${jsonEncode(m)}\n');
    } on Object {
      // peer gone
    }
  }

  Future<void> close() async {
    try {
      await socket.flush();
    } on Object {
      // already closed
    }
    socket.destroy();
    await _sub.cancel();
    _done();
  }
}

String _randomToken() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

enum MiniReturn { none, expand, close }

/// Main-process side: starts the mini player and relays between the two.
class MiniHost extends ChangeNotifier implements RemotePlayback {
  MiniHost(
    this._port, {
    MiniSpawner? spawner,
    Duration connectTimeout = const Duration(seconds: 15),
  }) : _spawner = spawner ?? spawnSelf,
       _connectTimeout = connectTimeout;

  final MiniHostPort _port;
  final MiniSpawner _spawner;
  final Duration _connectTimeout;

  bool _active = false;
  ServerSocket? _server;
  _Channel? _chan;
  MiniProcess? _proc;
  String _token = '';
  Json _snapshot = {};

  /// How the last mini player session ended.
  MiniReturn lastReturn = MiniReturn.none;

  @override
  bool get active => _active;

  /// Starts the mini player and waits for it to connect. Returns false if it
  /// could not start (the main window then keeps playing).
  Future<bool> launch({Offset? origin}) async {
    if (_active) return true;
    _active = true;
    lastReturn = MiniReturn.none;
    notifyListeners();
    final hello = Completer<void>();
    try {
      _token = _randomToken();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _snapshot = _port.pauseAndSnapshot();
      server.listen((socket) => _accept(socket, hello));
      final proc = await _spawner([
        '--mini',
        '--port=${server.port}',
        '--token=$_token',
        if (origin != null) '--pos=${origin.dx},${origin.dy}',
      ]);
      _proc = proc;
      unawaited(
        proc.exitCode.then((_) => _gone(), onError: (Object _) => _gone()),
      );
      await hello.future.timeout(_connectTimeout);
      return true;
    } on Object catch (e) {
      debugPrint('Mini player did not start: $e');
      final snap = _snapshot;
      _teardown(kill: true);
      _port.resumeLocal(snap);
      return false;
    }
  }

  void _accept(Socket socket, Completer<void> hello) {
    if (_chan != null) {
      socket.destroy(); // only one mini player at a time
      return;
    }
    final chan = _Channel(socket);
    var greeted = false;
    chan.messages.listen((m) {
      if (!greeted) {
        // The first message must carry our secret, or the peer is not our child.
        if (m['evt'] == 'hello' && m['token'] == _token && _chan == null) {
          greeted = true;
          _chan = chan;
          chan.send({'cmd': 'init', ..._snapshot});
          if (!hello.isCompleted) hello.complete();
        } else {
          chan.close();
        }
        return;
      }
      if (m['evt'] == 'expand' || m['evt'] == 'close') {
        unawaited(_finish(m));
      }
    });
    unawaited(
      chan.closed.then((_) {
        if (identical(_chan, chan)) _gone();
      }),
    );
  }

  Future<void> _finish(Json m) async {
    final expand = m['evt'] == 'expand';
    final prefs = m['prefs'];
    final history = m['history'];
    final state = m['state'];
    if (prefs is Map) {
      _port.applyPrefs({
        for (final k in miniPrefKeys)
          if (prefs.containsKey(k)) k: prefs[k],
      });
    }
    if (history is List) {
      _port.recordHistory([
        for (final h in history)
          if (h is Map<String, dynamic>) h,
      ]);
    }
    lastReturn = expand ? MiniReturn.expand : MiniReturn.close;
    // Inactive first, so the controller stops forwarding before it plays again.
    _teardown(kill: false);
    if (state is Map<String, dynamic>) {
      await _port.adopt(state, play: expand && state['playing'] == true);
    }
    if (expand) _port.bringToFront();
  }

  /// The mini player went away without saying goodbye (crash / killed).
  void _gone() {
    if (_active) _teardown(kill: false);
  }

  void _teardown({required bool kill}) {
    final chan = _chan;
    final server = _server;
    final proc = _proc;
    _chan = null;
    _server = null;
    _proc = null;
    _active = false;
    if (chan != null) unawaited(chan.close());
    if (server != null) unawaited(server.close());
    if (kill) proc?.kill();
    // The mini process can end after the main window started closing.
    if (!_disposed) notifyListeners();
  }

  void _send(Json m) => _chan?.send(m);

  // ---- RemotePlayback: what the main window forwards ----

  @override
  Future<void> open(List<String> paths, {int start = 0, Duration? at}) async =>
      _send({
        'cmd': 'open',
        'paths': paths,
        'start': start,
        if (at != null) 'posMs': at.inMilliseconds,
      });

  @override
  Future<void> add(List<String> paths) async =>
      _send({'cmd': 'add', 'paths': paths});

  @override
  void toggle() => _send({'cmd': 'toggle'});

  @override
  void next() => _send({'cmd': 'next'});

  @override
  void previous() => _send({'cmd': 'prev'});

  /// Ask the mini player to hand playback back to the main window.
  void bringBack() => _send({'cmd': 'return'});

  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _teardown(kill: false);
    _disposed = true;
    super.dispose();
  }
}

/// Arguments of a mini player process.
class MiniArgs {
  const MiniArgs({required this.port, required this.token, this.origin});
  final int port;
  final String token;
  final Offset? origin;
}

/// Returns the mini arguments if this process was started as a mini player.
MiniArgs? parseMiniArgs(List<String> args) {
  if (!args.contains('--mini')) return null;
  String? value(String name) {
    for (final a in args) {
      if (a.startsWith('--$name=')) return a.substring(name.length + 3);
    }
    return null;
  }

  final port = int.tryParse(value('port') ?? '');
  final token = value('token');
  if (port == null || token == null || token.isEmpty) return null;
  Offset? origin;
  final pos = value('pos')?.split(',');
  if (pos != null && pos.length == 2) {
    final x = double.tryParse(pos[0]), y = double.tryParse(pos[1]);
    if (x != null && y != null) origin = Offset(x, y);
  }
  return MiniArgs(port: port, token: token, origin: origin);
}

/// Mini-process side of the connection.
class MiniChild {
  MiniChild._(this._chan, this.init, this.origin);

  final _Channel _chan;

  /// What to play, as sent by the main window.
  final Json init;
  final Offset? origin;

  /// Commands from the main window after `init`.
  Stream<Json> get commands => _chan.messages;

  /// False once the main window has gone away.
  bool get mainAlive => !_chan.isClosed;

  /// Connects to the main window. Null if it cannot be reached.
  static Future<MiniChild?> connect(
    MiniArgs args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        args.port,
        timeout: timeout,
      );
      final chan = _Channel(socket);
      final first = chan.messages.firstWhere((m) => m['cmd'] == 'init');
      chan.send({'evt': 'hello', 'token': args.token});
      final init = await first.timeout(timeout);
      return MiniChild._(chan, init, args.origin);
    } on Object catch (e) {
      debugPrint('Could not reach the main window: $e');
      return null;
    }
  }

  /// Tells the main window how playback ended and closes the connection.
  /// Returns false if the main window was already gone (nothing delivered).
  Future<bool> finish(
    String evt, {
    required Json state,
    Json prefs = const {},
    List<Json> history = const [],
  }) async {
    if (_chan.isClosed) return false;
    _chan.send({
      'evt': evt,
      'state': state,
      'prefs': prefs,
      'history': history,
    });
    await _chan.close();
    return true;
  }
}
