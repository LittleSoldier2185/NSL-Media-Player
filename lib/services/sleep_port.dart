import '../player_controller/player_controller.dart';
import 'sleep_timer.dart';

/// Connects the sleep timer to the real player. While the separate mini
/// player window is playing, it can only be paused (its volume is not ours to
/// fade) and the time left in the file is unknown.
class ControllerSleepPort implements SleepPort {
  ControllerSleepPort(this._c);
  final NslPlayerController _c;

  bool get _remote => _c.remote?.active ?? false;

  @override
  double get volume => _c.player.state.volume;

  @override
  Future<void> setVolume(double v) => _c.player.setVolume(v.clamp(0, 100));

  @override
  Future<void> pause() async {
    if (_remote) {
      _c.remote!.pause();
    } else {
      await _c.player.pause();
    }
  }

  @override
  Duration? get remainingInItem {
    if (_remote) return null;
    final s = _c.player.state;
    if (_c.current == null || s.duration <= Duration.zero) return null;
    final left = s.duration - s.position;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  bool get canFade => !_remote;
}
