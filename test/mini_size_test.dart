import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/ui/mini_player.dart';

void main() {
  test('16:9 video gets a 420x236 window', () {
    expect(miniVideoSize(16 / 9), const Size(420, 236));
  });

  test('4:3 and square videos stay 420 wide and get taller', () {
    expect(miniVideoSize(4 / 3), const Size(420, 315));
    expect(miniVideoSize(1), const Size(420, 420));
  });

  test('portrait video is 480 tall with the matching width', () {
    expect(miniVideoSize(9 / 16), const Size(270, 480));
    expect(miniVideoSize(3 / 4), const Size(360, 480));
  });

  test('extreme shapes are limited so the controls still fit', () {
    expect(miniVideoSize(2.39).height, 180); // ultra-wide: not thinner
    expect(miniVideoSize(2.39).width, 420);
    expect(miniVideoSize(0.2).width, 270); // very tall: not narrower
    expect(miniVideoSize(0.2).height, 480);
  });

  group('user-resizable size', () {
    test('scale 1.0 is the default size', () {
      expect(miniVideoSizeAt(16 / 9, 1.0), const Size(420, 236));
    });

    test('a bigger scale keeps the video shape', () {
      final s = miniVideoSizeAt(16 / 9, 2.0);
      expect(s.width, 840);
      expect(s.width / s.height, closeTo(16 / 9, 0.01));
    });

    test('scale is limited: not too small, not too big', () {
      final small = miniVideoSizeAt(16 / 9, 0.01);
      expect(small.width, greaterThanOrEqualTo(220));
      expect(small.height, greaterThanOrEqualTo(120));
      final big = miniVideoSizeAt(16 / 9, 50);
      expect(big.width, lessThanOrEqualTo(1000));
      expect(big.height, lessThanOrEqualTo(720));
    });

    test('portrait video is limited by its height', () {
      final big = miniVideoSizeAt(9 / 16, 50);
      expect(big.height, lessThanOrEqualTo(720));
      expect(big.width / big.height, closeTo(9 / 16, 0.01));
    });

    test('the default size is always inside the allowed range', () {
      for (final a in [0.2, 9 / 16, 1.0, 4 / 3, 16 / 9, 2.39, 4.0]) {
        final base = miniVideoSize(a);
        expect(miniScaleMin(base), lessThanOrEqualTo(1.0));
        expect(miniScaleMax(base), greaterThanOrEqualTo(1.0));
      }
    });

    test('dragged width maps back to a scale and round-trips', () {
      final s = miniVideoSizeAt(16 / 9, 1.5);
      final scale = miniScaleForWidth(16 / 9, s.width);
      expect(miniVideoSizeAt(16 / 9, scale), s);
    });

    test('a bad scale falls back to the default size', () {
      expect(miniVideoSizeAt(16 / 9, double.nan), const Size(420, 236));
    });
  });

  test('a bad aspect falls back to 16:9', () {
    expect(miniVideoSize(double.nan), const Size(420, 236));
    expect(miniVideoSize(0), const Size(420, 236));
  });
}
