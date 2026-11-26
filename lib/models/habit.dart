import 'package:cloud_firestore/cloud_firestore.dart';

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime fromDay(String key) {
  final s = key.split('-').map(int.parse).toList();
  return DateTime(s[0], s[1], s[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool canMoveOneTimeTaskToToday(
  HabitSchedule previous,
  HabitSchedule updated,
  DateTime now,
) {
  final today = dayKey(now);
  final oldDate = previous.oneTimeDate;
  return previous.kind == 'oneTime' &&
      updated.kind == 'oneTime' &&
      oldDate != null &&
      oldDate.compareTo(today) < 0 &&
      previous.effectiveFrom.compareTo(today) <= 0 &&
      updated.oneTimeDate == today &&
      !updated.archived &&
      !updated.paused &&
      today.compareTo(dayKey(now.toUtc())) >= 0;
}

class HabitSchedule {
  final String effectiveFrom;
  final String name;
  final String description;
  final String category;
  final String kind;
  final String startDate;
  final String? endDate;
  final String? oneTimeDate;
  final List<int> weekdays;
  final int? timeMinutes;
  final bool remindersEnabled;
  final int leadMinutes;
  final int repeatMinutes;
  final bool paused;
  final bool archived;

  const HabitSchedule({
    required this.effectiveFrom,
    required this.name,
    required this.description,
    required this.category,
    required this.kind,
    required this.startDate,
    this.endDate,
    this.oneTimeDate,
    required this.weekdays,
    required this.timeMinutes,
    required this.remindersEnabled,
    required this.leadMinutes,
    required this.repeatMinutes,
    required this.paused,
    required this.archived,
  });

  factory HabitSchedule.fromMap(Map<String, dynamic> m) => HabitSchedule(
    effectiveFrom: m['effectiveFrom'] as String? ?? '1970-01-01',
    name: m['name'] as String? ?? 'Untitled task',
    description: m['description'] as String? ?? '',
    category: m['category'] as String? ?? 'Personal',
    kind: m['kind'] as String? ?? 'recurring',
    startDate: m['startDate'] as String? ?? '1970-01-01',
    endDate: m['endDate'] as String?,
    oneTimeDate: m['oneTimeDate'] as String?,
    weekdays: (m['weekdays'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    timeMinutes: (m['timeMinutes'] as num?)?.toInt(),
    remindersEnabled: m['remindersEnabled'] as bool? ?? false,
    leadMinutes: (m['leadMinutes'] as num?)?.toInt() ?? 2,
    repeatMinutes: (m['repeatMinutes'] as num?)?.toInt() ?? 2,
    paused: m['paused'] as bool? ?? false,
    archived: m['archived'] as bool? ?? false,
  );

  Map<String, dynamic> toDefinition() => {
    'name': name,
    'description': description,
    'category': category,
    'kind': kind,
    'startDate': startDate,
    'endDate': endDate,
    'oneTimeDate': oneTimeDate,
    'weekdays': weekdays,
    'timeMinutes': timeMinutes,
    'remindersEnabled': remindersEnabled,
    'leadMinutes': leadMinutes,
    'repeatMinutes': repeatMinutes,
    'paused': paused,
    'archived': archived,
  };

  bool occursOn(DateTime day) => _occursOn(dayKey(day), day.weekday);

  bool _occursOn(String key, int weekday) {
    if (paused ||
        archived ||
        key.compareTo(startDate) < 0 ||
        (endDate != null && key.compareTo(endDate!) > 0)) {
      return false;
    }
    if (kind == 'oneTime') return oneTimeDate == key;
    return weekdays.contains(weekday);
  }

  String get timeLabel {
    if (timeMinutes == null) return 'Anytime';
    final h = timeMinutes! ~/ 60;
    final m = timeMinutes! % 60;
    return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }
}

class HabitTask {
  final String id;
  final List<HabitSchedule> versions;
  final String? iconId;
  final String? deletedOn;
  const HabitTask({
    required this.id,
    required this.versions,
    this.iconId,
    this.deletedOn,
  });
  factory HabitTask.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final maps = (d.data()?['versions'] as List<dynamic>? ?? [])
        .cast<dynamic>();
    final versions = maps
        .map((v) => HabitSchedule.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
    return HabitTask(
      id: d.id,
      versions: versions,
      iconId: d.data()?['iconId'] as String?,
      deletedOn: d.data()?['deletedOn'] as String?,
    );
  }
  HabitSchedule? on(DateTime day) => _onDate(dayKey(day));

  HabitSchedule? _onDate(String key) {
    for (var i = versions.length - 1; i >= 0; i--) {
      final version = versions[i];
      if (version.effectiveFrom.compareTo(key) <= 0) return version;
    }
    return null;
  }

  HabitSchedule? occurrenceOn(
    DateTime day, {
    String? dateKey,
    bool recorded = false,
  }) {
    final key = dateKey ?? dayKey(day);
    final cutoff = deletedOn;
    if (cutoff != null &&
        (key.compareTo(cutoff) > 0 || (key == cutoff && !recorded))) {
      return null;
    }
    final version = _onDate(key);
    return version != null && version._occursOn(key, day.weekday)
        ? version
        : null;
  }

  bool scheduled(DateTime day) => occurrenceOn(day) != null;
  HabitSchedule get latest => versions.last;
  bool get isArchived => latest.archived;

  bool get isDeleted => deletedOn != null;

  HabitSchedule? reminderScheduleAt(DateTime now) {
    if (isDeleted || isArchived) return null;
    final schedule = on(now);
    if (schedule == null || schedule.paused || schedule.archived) return null;
    return schedule;
  }
}

class HabitEntry {
  final String taskId;
  final String date;
  final String status;
  const HabitEntry(this.taskId, this.date, this.status);
  factory HabitEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return HabitEntry(
      m['taskId'] as String? ?? '',
      m['date'] as String? ?? '',
      m['status'] as String? ?? 'pending',
    );
  }
}

class DayProgress {
  final int total;
  final int done;
  final int skipped;
  const DayProgress(this.total, this.done, this.skipped);
  double get fraction => total == 0 ? 0 : done / total;
  int get pending => total - done - skipped;
}

DayProgress progressFor(
  DateTime date,
  List<HabitTask> tasks,
  List<HabitEntry> entries,
) {
  final key = dayKey(date);
  final statusById = {
    for (final entry in entries)
      if (entry.date == key) entry.taskId: entry.status,
  };
  var total = 0, completed = 0, skipped = 0;
  for (final task in tasks) {
    if (task.occurrenceOn(
          date,
          dateKey: key,
          recorded: statusById.containsKey(task.id),
        ) ==
        null) {
      continue;
    }
    total++;
    switch (statusById[task.id]) {
      case 'completed':
        completed++;
      case 'skipped':
        skipped++;
    }
  }
  return DayProgress(total, completed, skipped);
}

Map<String, List<HabitEntry>> groupEntriesByDate(List<HabitEntry> entries) {
  final grouped = <String, List<HabitEntry>>{};
  for (final entry in entries) {
    (grouped[entry.date] ??= []).add(entry);
  }
  return grouped;
}

String statusFor(String taskId, DateTime date, List<HabitEntry> entries) {
  final key = dayKey(date);
  for (final e in entries) {
    if (e.taskId == taskId && e.date == key) return e.status;
  }
  return 'pending';
}
