import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'library_service.dart';

/// Private mode: media that is hidden from everything until you type a PIN.
///
/// This is a lock at the level of the app only. Nothing is encrypted and no
/// file is hidden on disk: anyone who opens the folder in File Explorer sees
/// the files. What this service decides is which paths count as private
/// ([isPrivate]) and whether the Private section is open ([unlocked]).
///
/// The PIN is never stored, only a salted, deliberately slow hash of it
/// (PBKDF2-HMAC-SHA256). Wrong tries are slowed down and the delay survives a
/// restart. The unlocked state lives in memory only, so the app always starts
/// locked.
class PrivateService extends ChangeNotifier {
  /// [file] and the other parameters are for tests.
  PrivateService({
    File? file,
    int iterations = defaultIterations,
    DateTime Function()? now,
    bool idleTimer = true,
  }) : _fileOverride = file,
       _iterations = iterations,
       _now = now ?? DateTime.now {
    _load();
    if (idleTimer) {
      _idle = Timer.periodic(const Duration(seconds: 15), (_) => checkIdle());
    }
  }

  static const defaultIterations = 100000;

  /// Wrong tries allowed before the waiting starts.
  static const freeTries = 5;

  static const maxWait = Duration(minutes: 15);

  final File? _fileOverride;
  final int _iterations;
  final DateTime Function() _now;
  Timer? _idle;

  // ---- saved state ----

  List<int>? _salt;
  List<int>? _hash;
  int _savedIterations = defaultIterations;
  int _failures = 0;
  DateTime? _blockedUntil;
  final Set<String> _files = {}; // tagged files, compared lower-case
  final Map<String, String> _fileNames = {}; // lower-case -> as saved

  /// Lock again after this many idle minutes (0 = never).
  int _autoLockMinutes = 10;

  /// Lock when the window is minimized.
  bool _lockOnMinimize = true;

  /// Hide the "Private" entry from the sidebar (open it with its shortcut).
  bool _hideEntry = false;

  /// Show "Private" instead of the file name in the window title and the
  /// Windows media panel while a private file plays.
  bool _maskTitles = true;

  bool _unlocked = false;
  DateTime _lastActive = DateTime.now();

  /// Called with the path of each private file that is playing when the app
  /// locks, so the player can stop; set by the app.
  VoidCallback? onLocked;

  /// The folders that were made private (owned by the private library).
  List<String> Function() folders = () => const [];

  // ---- state ----

  bool get hasPin => _hash != null;
  bool get unlocked => _unlocked && hasPin;
  int get autoLockMinutes => _autoLockMinutes;
  bool get lockOnMinimize => _lockOnMinimize;
  bool get hideEntry => _hideEntry;
  bool get maskTitles => _maskTitles;

  /// Files that were tagged one by one (in no private folder).
  List<String> get taggedFiles => [for (final k in _files) _fileNames[k] ?? k];

  /// True when [path] belongs to Private: tagged, or inside a private folder.
  /// This does not depend on the lock, so private files stay hidden from the
  /// normal pages whether or not Private is open.
  bool isPrivate(String? path) {
    if (path == null) return false;
    if (_files.contains(path.toLowerCase())) return true;
    for (final f in folders()) {
      if (LibraryService.isUnder(path, f)) return true;
    }
    return false;
  }

  /// How long until another PIN try is allowed (null = now).
  Duration? get waitLeft {
    final b = _blockedUntil;
    if (b == null) return null;
    final left = b.difference(_now());
    return left > Duration.zero ? left : null;
  }

  // ---- PIN ----

  /// Sets the first PIN (only when there is none) and opens Private.
  Future<bool> setPin(String pin) async {
    if (hasPin || pin.length < minPinLength) return false;
    await _storePin(pin);
    _unlocked = true;
    _touch();
    notifyListeners();
    return true;
  }

  static const minPinLength = 4;

  Future<void> _storePin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final iters = _iterations;
    _hash = await _derive(pin, salt, iters);
    _salt = salt;
    _savedIterations = iters;
    _failures = 0;
    _blockedUntil = null;
    _save();
  }

  /// Tries [pin]; true opens Private. A wrong PIN counts against the allowed
  /// tries, and after [freeTries] each further one makes you wait longer.
  Future<bool> unlock(String pin) async {
    if (!hasPin) return false;
    if (waitLeft != null) return false;
    final ok = await _matches(pin);
    if (ok) {
      _failures = 0;
      _blockedUntil = null;
      _unlocked = true;
      _touch();
      _save();
    } else {
      _failures++;
      if (_failures >= freeTries) {
        final secs = 30 * pow(2, _failures - freeTries).toInt();
        final wait = Duration(seconds: secs);
        _blockedUntil = _now().add(wait > maxWait ? maxWait : wait);
      }
      _save();
    }
    notifyListeners();
    return ok;
  }

  Future<bool> _matches(String pin) async {
    final h = _hash, s = _salt;
    if (h == null || s == null) return false;
    final got = await _derive(pin, s, _savedIterations);
    return _sameBytes(got, h);
  }

  /// Changes the PIN; needs the old one (even while open).
  Future<bool> changePin(String oldPin, String newPin) async {
    if (!hasPin || newPin.length < minPinLength) return false;
    if (waitLeft != null || !await _matches(oldPin)) return false;
    await _storePin(newPin);
    notifyListeners();
    return true;
  }

  /// Forgot the PIN: forgets the PIN and every tagged file (the files are not
  /// touched; they simply go back to the normal library). The private folders
  /// are for the caller to clear.
  void resetAll() {
    _hash = null;
    _salt = null;
    _files.clear();
    _fileNames.clear();
    _failures = 0;
    _blockedUntil = null;
    final was = _unlocked;
    _unlocked = false;
    _save();
    if (was) onLocked?.call();
    notifyListeners();
  }

  // ---- locking ----

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    onLocked?.call();
    notifyListeners();
  }

  /// Something happened in the app (a click, a key): restart the idle clock.
  void activity() => _lastActive = _now();

  void _touch() => _lastActive = _now();

  /// Locks when idle for longer than the setting. Runs every few seconds.
  void checkIdle() {
    if (!_unlocked || _autoLockMinutes <= 0) return;
    if (_now().difference(_lastActive) >= Duration(minutes: _autoLockMinutes)) {
      lock();
    }
  }

  /// The window was minimized.
  void windowMinimized() {
    if (_lockOnMinimize) lock();
  }

  // ---- settings ----

  set autoLockMinutes(int v) {
    _autoLockMinutes = v.clamp(0, 24 * 60);
    _save();
    notifyListeners();
  }

  set lockOnMinimize(bool v) {
    _lockOnMinimize = v;
    _save();
    notifyListeners();
  }

  set hideEntry(bool v) {
    _hideEntry = v;
    _save();
    notifyListeners();
  }

  set maskTitles(bool v) {
    _maskTitles = v;
    _save();
    notifyListeners();
  }

  // ---- tagged files ----

  /// Makes single files private (they stay where they are on disk).
  void addFiles(Iterable<String> paths) {
    var changed = false;
    for (final p in paths) {
      final k = p.toLowerCase();
      if (_files.add(k)) {
        _fileNames[k] = p;
        changed = true;
      }
    }
    if (!changed) return;
    _save();
    notifyListeners();
  }

  /// Takes files out of Private (back to the normal library).
  void removeFiles(Iterable<String> paths) {
    var changed = false;
    for (final p in paths) {
      final k = p.toLowerCase();
      if (_files.remove(k)) {
        _fileNames.remove(k);
        changed = true;
      }
    }
    if (!changed) return;
    _save();
    notifyListeners();
  }

  /// True when [path] was tagged as a single file.
  bool isTagged(String path) => _files.contains(path.toLowerCase());

  // ---- hashing ----

  /// PBKDF2-HMAC-SHA256, 32 bytes. Run in another isolate so the window does
  /// not freeze while it works.
  static Future<List<int>> _derive(String pin, List<int> salt, int iters) {
    if (iters <= 2000) return Future.value(pbkdf2(pin, salt, iters));
    return Isolate.run(() => pbkdf2(pin, salt, iters));
  }

  @visibleForTesting
  static List<int> pbkdf2(String pin, List<int> salt, int iters) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < iters; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  /// Compares without stopping at the first difference.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  // ---- file ----

  File? get _file {
    if (_fileOverride != null) return _fileOverride;
    final base = Platform.environment['APPDATA'];
    return base == null ? null : File('$base\\NSL Media Player\\private.json');
  }

  void _load() {
    try {
      final f = _file;
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map) return;
      final salt = j['salt'], hash = j['hash'];
      if (salt is String && hash is String) {
        _salt = base64Decode(salt);
        _hash = base64Decode(hash);
      }
      if (j['iter'] is int) _savedIterations = j['iter'] as int;
      if (j['fail'] is int) _failures = j['fail'] as int;
      if (j['until'] is int) {
        _blockedUntil = DateTime.fromMillisecondsSinceEpoch(j['until'] as int);
      }
      if (j['auto'] is int) _autoLockMinutes = j['auto'] as int;
      if (j['minimize'] is bool) _lockOnMinimize = j['minimize'] as bool;
      if (j['hide'] is bool) _hideEntry = j['hide'] as bool;
      if (j['mask'] is bool) _maskTitles = j['mask'] as bool;
      final files = j['files'];
      if (files is List) {
        for (final p in files.whereType<String>()) {
          _files.add(p.toLowerCase());
          _fileNames[p.toLowerCase()] = p;
        }
      }
    } on Object catch (e) {
      // A damaged file must not leave the app without a lock it had: keep
      // everything private-looking closed and start without a PIN.
      debugPrint('Could not read private settings: $e');
    }
  }

  void _save() {
    try {
      final f = _file;
      if (f == null) return;
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          if (_salt != null) 'salt': base64Encode(_salt!),
          if (_hash != null) 'hash': base64Encode(_hash!),
          'iter': _savedIterations,
          'fail': _failures,
          if (_blockedUntil != null)
            'until': _blockedUntil!.millisecondsSinceEpoch,
          'auto': _autoLockMinutes,
          'minimize': _lockOnMinimize,
          'hide': _hideEntry,
          'mask': _maskTitles,
          'files': taggedFiles,
        }),
      );
    } on Object catch (e) {
      debugPrint('Could not write private settings: $e');
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}
