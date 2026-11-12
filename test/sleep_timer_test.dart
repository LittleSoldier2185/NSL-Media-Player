import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/sleep_timer.dart';

class _FakePort implements SleepPort {
  @override
  double volume = 80;
  bool paused = false;
  @override
  Duration? remainingInItem;
  @override
  bool canFade = true;
  final volumes = <double>[];

  @override
  Future<void> setVolume(double v) async {
    volume = v;
    volumes.add(v);
  }

  @override
  Future<void> pause() async => paused = true;
}

void main() {
  late DateTime now;
  late _FakePort port;
  late SleepTimer timer;

  setUp(() {
    now = DateTime(2026, 11, 12, 22, 0);
    port = _FakePort();
    timer = SleepTimer(
      port,
      now: () => now,
      tick: const Duration(hours: 1), // the tests call check() themselves
      fade: () => const Duration(seconds: 10),
    );
  });
  tearDown(() => timer.dispose());

  test('countdown pauses when time is up, fading the last seconds', () async {
    timer.startCountdown(const Duration(minutes: 30));
    expect(timer.mode, SleepMode.countdown);
    expect(timer.remaining, const Duration(minutes: 30));

    now = now.add(const Duration(minutes: 29, seconds: 30));
    await timer.check();
    expect(port.paused, isFalse);
    expect(port.volumes, isEmpty); // still before the fade

    now = now.add(const Duration(seconds: 25)); // 5 s left of a 10 s fade
    await timer.check();
    expect(port.volume, closeTo(40, 0.01)); // half of 80
    expect(port.paused, isFalse);

    now = now.add(const Duration(seconds: 5));
    await timer.check();
    expect(port.paused, isTrue);
    expect(port.volume, 80); // put back for the next play
    expect(timer.active, isFalse);
  });

  test('clock time later today, or tomorrow when already past', () {
    timer.startAt(23, 30);
    expect(timer.deadline, DateTime(2026, 11, 12, 23, 30));
    timer.startAt(21, 0);
    expect(timer.deadline, DateTime(2026, 11, 13, 21, 0));
    expect(timer.mode, SleepMode.clock);
  });

  test('uses the clock, so a long computer sleep ends it at once', () async {
    timer.startCountdown(const Duration(minutes: 10));
    now = now.add(const Duration(hours: 5));
    await timer.check();
    expect(port.paused, isTrue);
  });

  test('end of file waits for the file, then pauses', () async {
    port.remainingInItem = const Duration(minutes: 3);
    timer.startEndOfItem();
    expect(timer.remaining, isNull);
    await timer.check();
    expect(port.paused, isFalse);

    port.remainingInItem = const Duration(seconds: 4);
    await timer.check();
    expect(port.volume, closeTo(32, 0.01)); // 4 s of 10 s
    port.remainingInItem = const Duration(milliseconds: 200);
    await timer.check();
    expect(port.paused, isTrue);
    expect(port.volume, 80);
  });

  test('end of file with unknown time keeps waiting', () async {
    port.remainingInItem = null;
    timer.startEndOfItem();
    await timer.check();
    expect(port.paused, isFalse);
    expect(timer.active, isTrue);
  });

  test('cancel during the fade restores the volume', () async {
    timer.startCountdown(const Duration(seconds: 6));
    await timer.check();
    expect(port.volume, lessThan(80));
    timer.cancel();
    expect(port.volume, 80);
    expect(timer.active, isFalse);
    expect(port.paused, isFalse);
  });

  test('no fade when another window plays: it just pauses', () async {
    port.canFade = false;
    timer.startCountdown(const Duration(seconds: 6));
    await timer.check();
    expect(port.volumes, isEmpty);
    now = now.add(const Duration(seconds: 6));
    await timer.check();
    expect(port.paused, isTrue);
  });
}
