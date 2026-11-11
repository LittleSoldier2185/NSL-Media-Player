import 'dart:math';

import 'package:flutter/foundation.dart';

import 'library_service.dart';

/// Result of [pickRandomVideos].
class RandomPicks {
  const RandomPicks(this.items, {required this.fellBack});

  /// The picked videos (fewer than asked if the library has fewer).
  final List<LibraryItem> items;

  /// True when "only unwatched" was asked for but every video has been played,
  /// so the pick came from all of them.
  final bool fellBack;
}

/// Picks up to [count] different videos at random.
///
/// With [onlyUnwatched] the choice is made among videos for which [played]
/// is false; when there are none left it falls back to every video (and says
/// so). [avoid] holds paths picked just before, so rolling again gives
/// something new whenever there is anything else to give.
RandomPicks pickRandomVideos(
  Iterable<LibraryItem> items, {
  required bool Function(String path) played,
  int count = 1,
  bool onlyUnwatched = true,
  Set<String> avoid = const {},
  Random? rng,
}) {
  final videos = [
    for (final i in items)
      if (i.isVideo) i,
  ];
  var pool = videos;
  var fellBack = false;
  if (onlyUnwatched) {
    final fresh = [
      for (final v in videos)
        if (!played(v.path)) v,
    ];
    if (fresh.isEmpty) {
      fellBack = videos.isNotEmpty;
    } else {
      pool = fresh;
    }
  }
  // Prefer videos that were not shown a moment ago; only if there are not
  // enough of those, fill up with the ones that were.
  final rand = rng ?? Random();
  final fresh = [
    for (final v in pool)
      if (!avoid.contains(v.path)) v,
  ]..shuffle(rand);
  final seen = [
    for (final v in pool)
      if (avoid.contains(v.path)) v,
  ]..shuffle(rand);
  final shuffled = [...fresh, ...seen];
  return RandomPicks(shuffled.take(count).toList(), fellBack: fellBack);
}

/// What the Home page shows for "random video": a few picks that stay put
/// across rebuilds until the user rolls again or changes the filter.
///
/// Reads the library and history through callbacks so it can be tested
/// without the player.
class RandomVideoModel extends ChangeNotifier {
  RandomVideoModel({
    required List<LibraryItem> Function() items,
    required Set<String> Function() played,
    Random? rng,
  }) : _items = items,
       _played = played,
       _rng = rng;

  /// How many videos are picked at a time (the Videos tab shows all three,
  /// the All tab shows the first).
  static const pickCount = 3;

  final List<LibraryItem> Function() _items;
  final Set<String> Function() _played;
  final Random? _rng;

  List<LibraryItem> picks = [];
  bool onlyUnwatched = true;

  /// True when everything was watched and the pick came from all videos.
  bool fellBack = false;

  /// Paths that had been played when the current picks were made.
  Set<String> _playedAtPick = const {};

  /// Whether [path] had been played before it was picked (for the label
  /// "never played" / "played before").
  bool wasPlayed(String path) => _playedAtPick.contains(path.toLowerCase());

  /// True when [picks] is empty because the library has no videos.
  bool get noVideos => !_items().any((i) => i.isVideo);

  /// Picks for the first time (or after the library filled up). Does not
  /// notify: it is meant to be called while building.
  void ensure() {
    if (picks.isEmpty) _pick(const {});
  }

  /// Different videos, if there are any others to show.
  void roll() {
    _pick({for (final p in picks) p.path});
    notifyListeners();
  }

  void setOnlyUnwatched(bool v) {
    if (v == onlyUnwatched) return;
    onlyUnwatched = v;
    _pick(const {});
    notifyListeners();
  }

  void _pick(Set<String> avoid) {
    final played = _played();
    _playedAtPick = played;
    final r = pickRandomVideos(
      _items(),
      played: (path) => played.contains(path.toLowerCase()),
      count: pickCount,
      onlyUnwatched: onlyUnwatched,
      avoid: avoid,
      rng: _rng,
    );
    picks = r.items;
    fellBack = r.fellBack;
  }
}
