import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../player_controller/player_controller.dart';
import '../services/media_types.dart';
import 'settings_service.dart';

class HistoryEntry {
  HistoryEntry({
    required this.path,
    required this.posMs,
    required this.durMs,
    required this.lastPlayed,
  });

  final String path;
  int posMs;
  int durMs;
  DateTime lastPlayed;

  String get title => fileNameOf(path);
  bool get isVideo => videoExtensions.contains(extensionOf(path));

  /// Worth offering under "Continue": started, and not (nearly) finished.
  bool get resumable => posMs > 5000 && (durMs <= 0 || posMs < durMs * 0.95);

  double get fraction => durMs <= 0 ? 0 : (posMs / durMs).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'p': path,
    'pos': posMs,
    'dur': durMs,
    't': lastPlayed.millisecondsSinceEpoch,
  };

  static HistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['p'], pos = j['pos'], dur = j['dur'], t = j['t'];
    if (p is! String || pos is! int || dur is! int || t is! int) return null;
    return HistoryEntry(
      path: p,
      posMs: pos,
      durMs: dur,
      lastPlayed: DateTime.fromMillisecondsSinceEpoch(t),
    );
  }
}

/// Records resume positions, daily watch time and play counts.
class HistoryService extends ChangeNotifier {
  /// [track] false makes this service record nothing (the separate mini
  /// player process reports to the main window instead of writing history).
  HistoryService(this._prefs, this._c, [this._settings, this._track = true]) {
    _load();
    _c.addListener(_onController);
    _c.player.stream.playing.listen((v) {
      _playing = v;
      if (!v) _persist();
    });
    _c.player.stream.position.listen(_onPosition);
    _c.player.stream.duration.listen((d) {
      _durMs = d.inMilliseconds;
    });
  }

  static const _maxEntries = 30;

  final SharedPreferences _prefs;
  final NslPlayerController _c;
  final AppSettings? _settings;
  final bool _track;
  bool get _enabled => _track && (_settings?.keepHistory ?? true);

  /// While true, a change of file is not counted as a new play: used when the
  /// queue is handed back from the mini player, which reports its own plays.
  bool _suspendCounting = false;

  Future<T> withoutCountingPlays<T>(Future<T> Function() body) async {
    _suspendCounting = true;
    try {
      return await body();
    } finally {
      _suspendCounting = false;
    }
  }

  /// Adds what was watched in a mini player process. Each entry has `path`,
  /// `seconds`, `posMs`, `durMs` and `plays` (see [MiniSessionTracker]).
  void recordExternal(List<Map<String, dynamic>> entries) {
    if (!_enabled) return;
    final today = dayKey(DateTime.now());
    for (final e in entries) {
      final path = e['path'];
      if (path is! String) continue;
      final seconds = e['seconds'] is num
          ? (e['seconds'] as num).toDouble()
          : 0.0;
      final plays = e['plays'] is int ? e['plays'] as int : 0;
      final pos = e['posMs'] is int ? e['posMs'] as int : 0;
      final dur = e['durMs'] is int ? e['durMs'] as int : 0;
      if (seconds > 0) daily[today] = (daily[today] ?? 0) + seconds;
      if (plays > 0) {
        final month = _monthPlays(DateTime.now());
        month[path] = (month[path] ?? 0) + plays;
      }
      final entry = _upsert(path, pos, dur);
      entry.posMs = pos;
      if (dur > 0) entry.durMs = dur;
    }
    _save();
  }

  Map<String, int> _monthPlays(DateTime d) =>
      plays.putIfAbsent(monthKey(d), () => {});

  final List<HistoryEntry> entries = []; // newest first
  final Map<String, double> daily = {}; // yyyy-MM-dd -> seconds
  final Map<String, Map<String, int>> plays = {}; // yyyy-MM -> path -> count

  String? _path;
  bool _playing = false;
  Duration? _lastPos;
  int _posMs = 0;
  int _durMs = 0;
  DateTime _lastSave = DateTime.now();

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  void _load() {
    try {
      final h = jsonDecode(_prefs.getString('history') ?? '[]');
      if (h is List) {
        entries.addAll(h.map(HistoryEntry.fromJson).whereType<HistoryEntry>());
      }
      final d = jsonDecode(_prefs.getString('daily') ?? '{}');
      if (d is Map) {
        d.forEach((k, v) {
          if (v is num) daily['$k'] = v.toDouble();
        });
      }
      final pl = jsonDecode(_prefs.getString('plays') ?? '{}');
      if (pl is Map) {
        pl.forEach((m, v) {
          if (v is Map) {
            plays['$m'] = {
              for (final e in v.entries)
                if (e.value is int) '${e.key}': e.value as int,
            };
          }
        });
      }
    } on FormatException {
      // corrupted prefs: start fresh
    }
  }

  void _onController() {
    final path = _c.currentPath;
    if (path == _path) return;
    if (!_enabled || _suspendCounting) {
      _path = path;
      return;
    }
    _persist(); // finalize the previous item
    _path = path;
    _lastPos = null;
    _posMs = 0;
    _durMs = 0;
    if (path == null) return;
    final month = plays.putIfAbsent(monthKey(DateTime.now()), () => {});
    month[path] = (month[path] ?? 0) + 1;
    _upsert(path, 0, 0);
    _save();
    notifyListeners();
  }

  void _onPosition(Duration pos) {
    if (!_enabled) return;
    _posMs = pos.inMilliseconds;
    final last = _lastPos;
    _lastPos = pos;
    if (_playing && last != null) {
      final d = pos - last;
      if (d > Duration.zero && d <= const Duration(seconds: 2)) {
        final k = dayKey(DateTime.now());
        daily[k] = (daily[k] ?? 0) + d.inMilliseconds / 1000;
      }
    }
    if (DateTime.now().difference(_lastSave) > const Duration(seconds: 5)) {
      _persist();
    }
  }

  HistoryEntry _upsert(String path, int pos, int dur) {
    var e = entries.where((x) => x.path == path).firstOrNull;
    if (e == null) {
      e = HistoryEntry(
        path: path,
        posMs: pos,
        durMs: dur,
        lastPlayed: DateTime.now(),
      );
    } else {
      entries.remove(e);
      e.lastPlayed = DateTime.now();
    }
    entries.insert(0, e);
    if (entries.length > _maxEntries)
      entries.removeRange(_maxEntries, entries.length);
    return e;
  }

  /// Removes all history; files are not touched.
  void clear() {
    entries.clear();
    daily.clear();
    plays.clear();
    _save();
  }

  void _persist() {
    if (!_enabled) return;
    final path = _path;
    if (path != null && _durMs > 0) {
      final e = entries.where((x) => x.path == path).firstOrNull;
      if (e != null) {
        e.posMs = _posMs;
        e.durMs = _durMs;
      }
    }
    _save();
  }

  void _save() {
    _lastSave = DateTime.now();
    // Keep only the last 62 days of watch time.
    final cutoff = dayKey(DateTime.now().subtract(const Duration(days: 62)));
    daily.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    _prefs.setString(
      'history',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    _prefs.setString('daily', jsonEncode(daily));
    _prefs.setString('plays', jsonEncode(plays));
    notifyListeners();
  }

  /// Entries to show under "Continue" (existing on disk is not checked here).
  List<HistoryEntry> get resumable => (_settings?.resume ?? true)
      ? entries.where((e) => e.resumable).take(3).toList()
      : const [];

  /// Watch seconds for the last 7 days, oldest first, with their dates.
  List<(DateTime, double)> get lastWeek {
    final today = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          return (d, daily[dayKey(d)] ?? 0.0);
        }(),
    ];
  }

  /// Most played this month: (path, count), best first.
  List<(String, int)> get topThisMonth {
    final m = plays[monthKey(DateTime.now())] ?? const {};
    final l = [for (final e in m.entries) (e.key, e.value)];
    l.sort((a, b) => b.$2.compareTo(a.$2));
    return l.take(3).toList();
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    super.dispose();
  }
}
