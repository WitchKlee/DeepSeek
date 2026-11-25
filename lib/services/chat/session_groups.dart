import '../../l10n/app_strings.dart';
import '../../models/chat_models.dart';

class SessionGroup {
  final String label;
  final List<SessionSummary> sessions;

  const SessionGroup({required this.label, required this.sessions});
}

/// Groups sessions by Today / Yesterday / 7 Days / 30 Days / YYYY-MM
/// matching `src/services/chat/sessionGroups.ts`.
List<SessionGroup> groupSessionsByTime(
  List<SessionSummary> sessions,
  AppStrings s, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day);

  final groups = <String, List<SessionSummary>>{};
  final order = <String>[];

  for (final item in sessions) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.updatedAt);
    final itemDayStart = DateTime(dt.year, dt.month, dt.day);
    final diffDays = todayStart.difference(itemDayStart).inDays;

    final String label;
    if (diffDays <= 0) {
      label = s.today;
    } else if (diffDays <= 1) {
      label = s.yesterday;
    } else if (diffDays < 7) {
      label = s.within7Days;
    } else if (diffDays < 30) {
      label = s.within30Days;
    } else {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      label = '$y-$m';
    }

    if (!groups.containsKey(label)) {
      groups[label] = [];
      order.add(label);
    }
    groups[label]!.add(item);
  }

  return order
      .map((label) => SessionGroup(label: label, sessions: groups[label]!))
      .toList();
}
