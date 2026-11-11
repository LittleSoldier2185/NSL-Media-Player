import '../services/history_service.dart';

/// 1:23 style clock from milliseconds.
String clockText(int ms) {
  final d = Duration(milliseconds: ms);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s'
      : '${d.inMinutes}:$s';
}

/// "just now", "3 h ago", "yesterday", "5 days ago".
String agoText(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inHours < 48) return 'yesterday';
  return '${d.inDays} days ago';
}

/// "12:04 of 41:30" (or just the position when the length is unknown).
String progressText(HistoryEntry e) => e.durMs > 0
    ? '${clockText(e.posMs)} of ${clockText(e.durMs)}'
    : clockText(e.posMs);

/// "09:40" (24-hour).
String timeOfDayText(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The groups the History page puts played files under.
enum HistoryDay {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('Earlier this week'),
  earlier('Earlier');

  const HistoryDay(this.label);
  final String label;
}

/// Which [HistoryDay] group [t] belongs to, by calendar day (not by 24-hour
/// distance, so 23:50 last night is "Yesterday" at 00:10).
HistoryDay historyDay(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return HistoryDay.today;
  if (diff == 1) return HistoryDay.yesterday;
  if (diff < 7) return HistoryDay.thisWeek;
  return HistoryDay.earlier;
}
