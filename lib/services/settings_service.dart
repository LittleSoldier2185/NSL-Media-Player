import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// Persisted appearance settings (theme mode + accent color).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
    : themeMode = _readMode(_prefs.getString('themeMode')),
      accent = Color(_prefs.getInt('accent') ?? defaultAccent.toARGB32());

  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;
  ThemeMode themeMode;
  Color accent;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  static ThemeMode _readMode(String? s) => ThemeMode.values.firstWhere(
    (m) => m.name == s,
    orElse: () => ThemeMode.dark,
  );

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _prefs.setString('themeMode', m.name);
    notifyListeners();
  }

  /// Switch to audio-only automatically while the window is minimized.
  bool get autoAudioOnly => _prefs.getBool('autoAudioOnly') ?? false;

  void setAutoAudioOnly(bool v) {
    _prefs.setBool('autoAudioOnly', v);
    notifyListeners();
  }

  /// Mini player window opacity in percent (20-100).
  int get miniOpacity => _prefs.getInt('miniOpacity') ?? 72;
  set miniOpacity(int v) => _prefs.setInt('miniOpacity', v.clamp(20, 100));

  bool get miniOnTop => _prefs.getBool('miniOnTop') ?? true;
  set miniOnTop(bool v) => _prefs.setBool('miniOnTop', v);

  Offset? get miniPosition {
    final l = _prefs.getStringList('miniPos');
    if (l == null || l.length != 2) return null;
    final x = double.tryParse(l[0]), y = double.tryParse(l[1]);
    return x == null || y == null ? null : Offset(x, y);
  }

  set miniPosition(Offset? o) => o == null
      ? _prefs.remove('miniPos')
      : _prefs.setStringList('miniPos', [o.dx.toString(), o.dy.toString()]);

  /// Saved window bounds as [x, y, width, height], or null.
  Rect? get windowBounds {
    final l = _prefs.getStringList('windowBounds');
    if (l == null || l.length != 4) return null;
    final v = l.map(double.tryParse).toList();
    if (v.contains(null)) return null;
    return Rect.fromLTWH(v[0]!, v[1]!, v[2]!, v[3]!);
  }

  void saveWindowBounds(Rect r) => _prefs.setStringList('windowBounds', [
    r.left.toString(),
    r.top.toString(),
    r.width.toString(),
    r.height.toString(),
  ]);

  // --- General ---
  bool get rememberWindow => _prefs.getBool('rememberWindow') ?? true;

  // --- Playback ---
  bool get resume => _prefs.getBool('resume') ?? true;
  bool get autoNext => _prefs.getBool('autoNext') ?? true;

  /// Volume applied at startup, or null to keep the last used volume.
  double? get defaultVolume => _prefs.getDouble('defaultVolume');
  double get defaultSpeed => _prefs.getDouble('defaultSpeed') ?? 1.0;
  int get seekStep => _prefs.getInt('seekStep') ?? 5;

  // --- Video ---
  /// 'auto' | 'on' | 'off'
  String get hwdec => _prefs.getString('hwdec') ?? 'auto';

  /// Start (and keep) video files in audio-only mode.
  bool get audioOnlyDefault => _prefs.getBool('audioOnlyDefault') ?? false;

  // --- Mini player ---
  /// Show the picture of videos in the mini player (otherwise sound only).
  bool get miniShowVideo => _prefs.getBool('miniShowVideo') ?? true;

  /// Size the user gave the mini player's picture-in-picture window, as a
  /// multiple of its default size (1.0).
  double get miniScale => _prefs.getDouble('miniScale') ?? 1.0;
  set miniScale(double v) => _prefs.setDouble('miniScale', v);

  /// Width the user gave the mini player's audio card.
  double get miniCardWidth => _prefs.getDouble('miniCardWidth') ?? 420.0;
  set miniCardWidth(double v) => _prefs.setDouble('miniCardWidth', v);

  /// Forget the sizes the user dragged the mini player to.
  void resetMiniSize() {
    _prefs.remove('miniScale');
    _prefs.remove('miniCardWidth');
    notifyListeners();
  }

  bool get miniRememberPos => _prefs.getBool('miniRememberPos') ?? true;

  // --- Library ---
  bool get keepHistory => _prefs.getBool('keepHistory') ?? true;

  /// Stores [value] under [key] (bool / int / double / String) and notifies.
  void put(String key, Object value) {
    switch (value) {
      case bool v:
        _prefs.setBool(key, v);
      case int v:
        _prefs.setInt(key, v);
      case double v:
        _prefs.setDouble(key, v);
      case String v:
        _prefs.setString(key, v);
    }
    notifyListeners();
  }

  void setAccent(Color c) {
    accent = c;
    _prefs.setInt('accent', c.toARGB32());
    notifyListeners();
  }
}
