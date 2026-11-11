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

  test('a bad aspect falls back to 16:9', () {
    expect(miniVideoSize(double.nan), const Size(420, 236));
    expect(miniVideoSize(0), const Size(420, 236));
  });
}
