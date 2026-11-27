import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/models/habit.dart';

HabitSchedule schedule({
  String effective = '2026-11-20',
  String name = 'Morning exercise',
  bool paused = false,
  bool archived = false,
  String? oneTimeDate,
  List<int> weekdays = const [1, 3, 5],
  int? timeMinutes = 420,
}) => HabitSchedule(
  effectiveFrom: effective,
  name: name,
  description: '',
  category: 'Health',
  kind: oneTimeDate == null ? 'recurring' : 'oneTime',
  oneTimeDate: oneTimeDate,
  startDate: '2026-11-20',
  weekdays: weekdays,
  timeMinutes: timeMinutes,
  remindersEnabled: true,
  leadMinutes: 2,
  repeatMinutes: 2,
  paused: paused,
  archived: archived,
);

void main() {
  test('Mon/Wed/Fri is not scheduled on Tuesday', () {
    final t = HabitTask(id: 'a', versions: [schedule()]);
    expect(t.scheduled(DateTime(2026, 11, 23)), isTrue);
    expect(t.scheduled(DateTime(2026, 11, 24)), isFalse);
  });
  test('future edit does not alter previous occurrences', () {
    final t = HabitTask(
      id: 'a',
      versions: [
        schedule(),
        schedule(effective: '2026-11-25', paused: true),
      ],
    );
    expect(t.on(DateTime(2026, 11, 23))!.paused, isFalse);
    expect(t.on(DateTime(2026, 11, 26))!.paused, isTrue);
  });
  test('occurrences prefer the last applicable revision in append order', () {
    final task = HabitTask(
      id: 'history',
      versions: [
        schedule(effective: '2026-11-20', name: 'Original'),
        schedule(effective: '2026-11-27', name: 'Future'),
        schedule(effective: '2026-11-23', name: 'Newer revision'),
        schedule(effective: '2026-11-23', name: 'Latest same day'),
      ],
    );
    expect(task.occurrenceOn(DateTime(2026, 11, 23))?.name, 'Latest same day');
    expect(task.occurrenceOn(DateTime(2026, 11, 25))?.name, 'Latest same day');
    expect(task.occurrenceOn(DateTime(2026, 11, 24)), isNull);
    expect(task.on(DateTime(2026, 11, 20))?.name, 'Original');
  });

  test('a saved archive takes effect in lists before the schedule changes', () {
    final task = HabitTask(
      id: 'a',
      versions: [
        schedule(),
        schedule(effective: '2026-11-25', archived: true),
      ],
    );

    expect(task.isArchived, isTrue);
    expect(task.scheduled(DateTime(2026, 11, 23)), isTrue);
    expect(task.scheduled(DateTime(2026, 11, 25)), isFalse);
  });
  test('overdue one-time tasks use their original completion date', () {
    final task = HabitTask(
      id: 'one-time',
      versions: [schedule(oneTimeDate: '2026-11-25')],
    );
    expect(task.completionDate(DateTime(2026, 11, 24)), isNull);
    expect(
      task.completionDate(DateTime(2026, 11, 25, 12)),
      DateTime(2026, 11, 25),
    );
    expect(task.completionDate(DateTime(2026, 11, 26)), DateTime(2026, 11, 25));

    final recurring = HabitTask(id: 'recurring', versions: [schedule()]);
    expect(recurring.completionDate(DateTime(2026, 11, 26)), isNull);
  });

  test(
    'same-day edits change the schedule and retain recorded occurrences',
    () {
      final day = DateTime(2026, 11, 25);
      final original = schedule(timeMinutes: 420);
      final changed = HabitTask(
        id: 'a',
        versions: [
          original,
          schedule(effective: '2026-11-25', timeMinutes: 600),
        ],
      );
      expect(changed.occurrenceOn(day)?.timeMinutes, 600);
      expect(changed.occurrenceOn(DateTime(2026, 11, 23))?.timeMinutes, 420);
      final paused = HabitTask(
        id: 'a',
        versions: [
          original,
          schedule(effective: '2026-11-25', paused: true),
        ],
      );
      expect(paused.occurrenceOn(day), isNull);
      expect(paused.occurrenceOn(day, recorded: true), original);
      expect(
        progressFor(
          day,
          [paused],
          const [HabitEntry('a', '2026-11-25', 'skipped')],
        ).skipped,
        1,
      );
    },
  );

  test('task list sorts untimed by creation, then timed by date and time', () {
    final now = DateTime(2026, 11, 25);
    final older = HabitTask(
      id: 'z-older',
      createdAt: DateTime.utc(2026, 11, 20, 10),
      versions: [schedule(timeMinutes: null, oneTimeDate: '2026-11-30')],
    );
    final newer = HabitTask(
      id: 'a-newer',
      createdAt: DateTime.utc(2026, 11, 20, 11),
      versions: [schedule(timeMinutes: null)],
    );
    final revised = HabitTask(
      id: 'revised',
      versions: [
        schedule(timeMinutes: 300),
        schedule(effective: '2026-11-26', timeMinutes: 600),
      ],
    );
    final sameDayEarlier = HabitTask(
      id: 'earlier',
      versions: [schedule(timeMinutes: 500, oneTimeDate: '2026-11-27')],
    );
    final laterDay = HabitTask(
      id: 'later',
      versions: [schedule(timeMinutes: 180, oneTimeDate: '2026-11-28')],
    );
    final paused = HabitTask(id: 'paused', versions: [schedule(paused: true)]);
    final ordered = orderTasksForList([
      laterDay,
      newer,
      revised,
      paused,
      older,
      sameDayEarlier,
    ], now);
    expect(ordered.map((row) => row.task.id), [
      'z-older',
      'a-newer',
      'earlier',
      'revised',
      'later',
      'paused',
    ]);
    expect(revised.taskListOccurrenceDate(now), '2026-11-27');
    expect(revised.occurrenceOn(now)?.timeMinutes, 300);
  });

  test('deletion keeps past and recorded same-day progress only', () {
    final task = HabitTask(
      id: 'a',
      versions: [schedule()],
      deletedOn: '2026-11-25',
    );
    final deletedDay = DateTime(2026, 11, 25);
    expect(task.isDeleted, isTrue);
    expect(task.scheduled(DateTime(2026, 11, 23)), isTrue);
    expect(task.scheduled(deletedDay), isFalse);
    expect(task.scheduled(DateTime(2026, 11, 27)), isFalse);
    expect(task.reminderScheduleAt(deletedDay), isNull);
    expect(
      progressFor(
        deletedDay,
        [task],
        [const HabitEntry('a', '2026-11-25', 'completed')],
      ).done,
      1,
    );
  });

  test(
    'archiving suppresses reminders even for an occurrence still pending today',
    () {
      final today = DateTime(2026, 11, 23, 8);
      final task = HabitTask(
        id: 'pending-task',
        versions: [
          schedule(),
          schedule(effective: '2026-11-24', archived: true),
        ],
      );

      expect(task.on(today)!.archived, isFalse);
      expect(task.scheduled(today), isTrue);
      expect(statusFor(task.id, today, const []), 'pending');
      expect(task.reminderScheduleAt(today), isNull);
      expect(
        HabitTask(
          id: 'active-task',
          versions: [schedule()],
        ).reminderScheduleAt(today),
        isNotNull,
      );
    },
  );

  test(
    'a missed one-time task can move to today without changing yesterday',
    () {
      final today = DateTime.utc(2026, 11, 26, 5);
      final original = schedule(oneTimeDate: '2026-11-25');
      final moved = schedule(
        effective: '2026-11-26',
        oneTimeDate: '2026-11-26',
      );
      expect(canMoveOneTimeTaskToToday(original, moved, today), isTrue);
      expect(canMoveOneTimeTaskToToday(schedule(), moved, today), isFalse);
      expect(canMoveOneTimeTaskToToday(moved, moved, today), isFalse);
      expect(canMoveOneTimeTaskToToday(original, schedule(), today), isFalse);

      final task = HabitTask(id: 'one-time', versions: [original, moved]);
      expect(task.on(DateTime.utc(2026, 11, 25)), same(original));
      expect(task.on(today), same(moved));
      expect(task.scheduled(today), isTrue);
    },
  );
  test('progress ignores unrelated and unscheduled tasks', () {
    final a = HabitTask(id: 'a', versions: [schedule()]);
    final b = HabitTask(
      id: 'b',
      versions: [schedule(name: 'Read')],
    );
    final entries = [
      const HabitEntry('a', '2026-11-23', 'completed'),
      const HabitEntry('b', '2026-11-23', 'skipped'),
    ];
    final result = progressFor(DateTime(2026, 11, 23), [a, b], entries);
    expect(result.total, 2);
    expect(result.done, 1);
    expect(result.skipped, 1);
    expect(result.fraction, .5);
    expect(progressFor(DateTime(2026, 11, 24), [a, b], entries).total, 0);
  });
  test('missing entry means Pending; not Missed', () {
    expect(statusFor('a', DateTime(2026, 11, 23), const []), 'pending');
  });
}
