/// Decides when a playing video should drop to sound only because its picture
/// is not on screen (the user is browsing Library, Photos, Books, ...), and
/// when to bring the picture back.
///
/// It only undoes what it did itself: a video the user put in sound-only mode
/// stays that way when they come back to the player.
class HubAudioOnly {
  bool _switched = false;

  /// True while sound-only mode was set by this policy.
  bool get switched => _switched;

  /// Call whenever the page, the track or the mode changes. Returns `true`
  /// when sound-only should be turned on, `false` when it should be turned
  /// off again, and `null` when nothing needs to change.
  ///
  /// [away] means the player page is not the one showing.
  bool? update({
    required bool away,
    required bool enabled,
    required bool hasVideo,
    required bool audioOnly,
  }) {
    if (away && enabled && hasVideo && !audioOnly) {
      _switched = true;
      return true;
    }
    if (_switched && !away) {
      _switched = false;
      return audioOnly ? false : null;
    }
    // The user turned sound-only mode off by hand while we held it on, or the
    // video ended: nothing of ours is left to undo.
    if (_switched && !audioOnly) _switched = false;
    if (_switched && !hasVideo) _switched = false;
    return null;
  }
}
