import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/hub_audio.dart';

void main() {
  late HubAudioOnly h;
  setUp(() => h = HubAudioOnly());

  bool? update(
    HubAudioOnly h, {
    bool away = true,
    bool enabled = true,
    bool hasVideo = true,
    bool audioOnly = false,
  }) => h.update(
    away: away,
    enabled: enabled,
    hasVideo: hasVideo,
    audioOnly: audioOnly,
  );

  test('a playing video drops to sound only when you leave the player', () {
    expect(update(h), isTrue);
    expect(h.switched, isTrue);
  });

  test('it comes back when you return to the player', () {
    expect(update(h), isTrue);
    // The controller reports sound-only now.
    expect(update(h, audioOnly: true), isNull); // still away: nothing to do
    expect(update(h, away: false, audioOnly: true), isFalse);
    expect(h.switched, isFalse);
    // Back on the player and showing the picture: nothing left to do.
    expect(update(h, away: false), isNull);
  });

  test('music and idle players are left alone', () {
    expect(update(h, hasVideo: false), isNull);
    expect(h.switched, isFalse);
  });

  test('turned off in settings: never switches', () {
    expect(update(h, enabled: false), isNull);
  });

  test('a video the user already put in sound-only mode stays that way', () {
    // Not our doing: we must not undo it on return.
    expect(update(h, audioOnly: true), isNull);
    expect(update(h, away: false, audioOnly: true), isNull);
    expect(h.switched, isFalse);
  });

  test('if the user turns the picture back on while away, we let go', () {
    expect(update(h), isTrue);
    expect(update(h, audioOnly: false, away: true), isTrue); // asks again
    // But returning with sound-only already off asks for nothing.
    final g = HubAudioOnly();
    expect(update(g), isTrue);
    expect(update(g, away: false, audioOnly: false), isNull);
    expect(g.switched, isFalse);
  });

  test('a new video while away drops to sound only too', () {
    expect(update(h), isTrue);
    expect(update(h, audioOnly: true), isNull);
    // Next track is a video again; the controller still says sound only.
    expect(update(h, audioOnly: true), isNull);
    // Back on the player: restored once.
    expect(update(h, away: false, audioOnly: true), isFalse);
  });
}
