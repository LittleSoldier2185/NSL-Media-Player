import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/ui/time_format.dart';

void main() {
  test('clockText', () {
    expect(clockText(0), '0:00');
    expect(clockText(12000), '0:12');
    expect(clockText(754000), '12:34');
    expect(clockText(3723000), '1:02:03');
  });

  group('agoText', () {
    final now = DateTime(2026, 11, 12, 12);
    test('minutes, hours, yesterday, days', () {
      expect(
        agoText(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
      expect(
        agoText(now.subtract(const Duration(minutes: 15)), now: now),
        '15 min ago',
      );
      expect(
        agoText(now.subtract(const Duration(hours: 3)), now: now),
        '3 h ago',
      );
      expect(
        agoText(now.subtract(const Duration(hours: 30)), now: now),
        'yesterday',
      );
      expect(
        agoText(now.subtract(const Duration(days: 5)), now: now),
        '5 days ago',
      );
    });
  });

  group('historyDay', () {
    final now = DateTime(2026, 11, 12, 0, 10); // just after midnight
    test('groups by calendar day, not by 24 hours', () {
      expect(
        historyDay(DateTime(2026, 11, 12, 0, 5), now: now),
        HistoryDay.today,
      );
      // 23:50 last night is 20 minutes ago but already "Yesterday".
      expect(
        historyDay(DateTime(2026, 11, 11, 23, 50), now: now),
        HistoryDay.yesterday,
      );
      expect(
        historyDay(DateTime(2026, 11, 10, 12), now: now),
        HistoryDay.thisWeek,
      );
      expect(
        historyDay(DateTime(2026, 11, 6, 12), now: now),
        HistoryDay.thisWeek,
      );
      expect(
        historyDay(DateTime(2026, 11, 5, 12), now: now),
        HistoryDay.earlier,
      );
    });

    test('has readable labels', () {
      expect(HistoryDay.today.label, 'Today');
      expect(HistoryDay.thisWeek.label, 'Earlier this week');
    });
  });

  test('timeOfDayText pads', () {
    expect(timeOfDayText(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });
}
