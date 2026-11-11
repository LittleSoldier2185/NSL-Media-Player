import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Home page's stats row puts a card with a Chart/Table SegmentedButton
/// and a fixed-height chart next to a list card, inside IntrinsicHeight so the
/// two cards are equally tall. HomePage itself needs the native player, so
/// this checks the same structure at the window sizes the layout switches at.
void main() {
  Widget stats(double width) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(child: Text('Last 7 days')),
                              SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text('Chart'),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text('Table'),
                                  ),
                                ],
                                selected: const {false},
                                onSelectionChanged: (_) {},
                              ),
                            ],
                          ),
                          const Text('0h 7m', style: TextStyle(fontSize: 44)),
                          SizedBox(
                            height: 150,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < 7; i++)
                                  Expanded(
                                    child: MouseRegion(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Stack(
                                              alignment: Alignment.bottomCenter,
                                              children: [
                                                FractionallySizedBox(
                                                  heightFactor: 0.3,
                                                  child: Container(width: 24),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Text('Mon'),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Most played this month'),
                          Text('1  Some file name.mp4'),
                          Text('2  Another file name.mp4'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final w in [1180.0, 1000.0, 820.0, 760.0]) {
    testWidgets('stats row lays out at ${w.toInt()}px', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(stats(w));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('the recent row never gets a tile narrower than a readable width', () {
    // Same arithmetic as HomePage._recent.
    for (var w = 480.0; w <= 1180; w += 20) {
      const gap = 16.0;
      final cols = ((w + gap) / (176 + gap)).floor().clamp(2, 6);
      final tileW = (w - gap * (cols - 1)) / cols;
      expect(cols, inInclusiveRange(2, 6));
      expect(tileW, greaterThanOrEqualTo(150), reason: 'width $w');
    }
  });
}
