import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/services/media_types.dart';

void main() {
  test('detects supported media', () {
    expect(isSupportedMedia(r'C:\a\b.MP4'), isTrue);
    expect(isSupportedMedia('x.txt'), isFalse);
    expect(firstMediaArg(['--x', 'a.flac']), 'a.flac');
  });
}
