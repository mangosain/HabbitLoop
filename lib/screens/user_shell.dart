import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../core/palette.dart';
import '../models/habit.dart';
import '../models/daily_quotes.dart';
import '../services/habit_backend.dart';
import '../services/daily_quote_rotation.dart';
import '../widgets/calendar_board.dart';
import '../widgets/common.dart';
import '../widgets/daily_quote_card.dart';
import '../widgets/brand.dart';
import '../widgets/shared_element.dart';
import '../widgets/task_icons.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/motion_switcher.dart';
import 'task_editor.dart';
import 'settings.dart';

class _HabitData extends InheritedWidget {
  const _HabitData({
    required this.tasks,
    required this.entries,
    required super.child,
  });

  final AsyncSnapshot<List<HabitTask>> tasks;
  final AsyncSnapshot<List<HabitEntry>> entries;

  @override
  bool updateShouldNotify(_HabitData oldWidget) =>
      tasks != oldWidget.tasks || entries != oldWidget.entries;
}

class HabitLiveBuilder extends StatelessWidget {
  const HabitLiveBuilder({super.key, required this.builder});
  final Widget Function(List<HabitTask>, List<HabitEntry>) builder;

  @override
  Widget build(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<_HabitData>()!;
    final tasks = data.tasks;
    final entries = data.entries;
    if (tasks.hasError || entries.hasError) {
      return Center(
        child: Text('Unable to read habits: ${tasks.error ?? entries.error}'),
      );
    }
    if (!tasks.hasData || !entries.hasData) {
      return const Center(
        child: HabitLoadingIndicator(label: 'Loading habits'),
      );
    }
    return builder(tasks.data!, entries.data!);
  }
}

class UserShell extends StatefulWidget {
  const UserShell({super.key, required this.uid, required this.displayName});
  final String uid, displayName;
  @override
  State<UserShell> createState() => _UserShellState();
}

class _UserShellState extends State<UserShell> {
  int index = 0;
  late final _tasks = HabitBackend.instance.tasks(widget.uid);
  late final _entries = HabitBackend.instance.entries(widget.uid);

  @override
  Widget build(BuildContext context) {
    final child = _buildScaffold();
    return StreamBuilder<List<HabitTask>>(
      stream: _tasks,
      builder: (context, tasks) => StreamBuilder<List<HabitEntry>>(
        stream: _entries,
        builder: (context, entries) =>
            _HabitData(tasks: tasks, entries: entries, child: child),
      ),
    );
  }

  Widget _buildScaffold() => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          if (index == 0) const BrandHeader(),
          Expanded(
            child: MotionSwitcher(
              child: KeyedSubtree(
                key: ValueKey(index),
                child: switch (index) {
                  0 => UserDashboard(
                    uid: widget.uid,
                    displayName: widget.displayName,
                    openTasks: () => setState(() => index = 1),
                  ),
                  1 => TaskListPage(uid: widget.uid, editable: true),
                  2 => _CalendarPage(uid: widget.uid),
                  3 => StatsPage(uid: widget.uid),
                  _ => SettingsPage(uid: widget.uid, isAdmin: false),
                },
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => setState(() => index = i),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      indicatorColor: AppPalette.mint,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.checklist_rounded),
          label: 'Tasks',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'Calendar',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Insights',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          label: 'Settings',
        ),
      ],
    ),
  );
}

class UserDashboard extends StatelessWidget {
  const UserDashboard({
    super.key,
    required this.uid,
    required this.displayName,
    required this.openTasks,
  });
  final String uid, displayName;
  final VoidCallback openTasks;
  @override
  Widget build(BuildContext context) => HabitLiveBuilder(
    builder: (tasks, entries) {
      final today = DateTime.now();
      final todayKey = dayKey(today);
      final todayEntries = entries
          .where((entry) => entry.date == todayKey)
          .toList();
      final p = progressFor(today, tasks, todayEntries);
      final scheduled = tasks
          .where((t) => !t.isDeleted && !t.isArchived && t.scheduled(today))
          .toList();
      final streak = currentStreak(tasks, entries);
      return ListView(
        padding: const EdgeInsets.fromLTRB(19, 22, 19, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi, ${displayName.split(' ').first}! 👋',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(today),
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SharedIcon(
                tag: remindersHeroTag,
                icon: Icons.notifications_none_rounded,
                child: RoundAction(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notification preferences',
                  onPressed: () => Navigator.of(context).push(
                    sharedRoute<void>(
                      context,
                      SettingsPage(
                        uid: uid,
                        isAdmin: false,
                        animateReminders: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: SoftCard(
                    color: AppPalette.mint,
                    child: Column(
                      children: [
                        ProgressRing(
                          progress: p.fraction,
                          center: '${p.done}/${p.total}',
                          subtitle: 'Tasks',
                          size: 128,
                          stroke: 11,
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Today’s progress',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppPalette.deepGreen,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder(
                          valueListenable: DailyQuoteRotation.instance.current,
                          builder: (context, quote, _) => DailyQuoteCard(
                            quote?.text ?? quoteForDay(DateTime.now()),
                            author: quote?.author,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SoftCard(
                        color: AppPalette.peach,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              color: Color(0xFFE88E55),
                              size: 22,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$streak day',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Text(
                                    'Streak',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppPalette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          CalendarBoard(uid: uid, tasks: tasks, entries: entries),
          const SizedBox(height: 21),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Today’s tasks',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(onPressed: openTasks, child: const Text('View all →')),
            ],
          ),
          const SizedBox(height: 4),
          if (scheduled.isEmpty)
            const SoftCard(
              child: EmptyMessage(
                title: 'Nothing planned today',
                subtitle: 'Add a task and start your rhythm.',
              ),
            ),
          ...scheduled
              .take(5)
              .map(
                (task) => DailyTaskTile(
                  uid: uid,
                  task: task,
                  date: today,
                  entries: todayEntries,
                ),
              ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: openTasks,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Manage tasks'),
          ),
        ],
      );
    },
  );
}

class DailyTaskTile extends StatelessWidget {
  const DailyTaskTile({
    super.key,
    required this.uid,
    required this.task,
    required this.date,
    required this.entries,
    this.readOnly = false,
    this.onEdit,
  });
  final String uid;
  final HabitTask task;
  final DateTime date;
  final List<HabitEntry> entries;
  final bool readOnly;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final s = task.on(date)!;
    final status = statusFor(task.id, date, entries);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: taskCategoryColor(s.category),
              child: Icon(
                taskIcon(s.name, s.category, iconId: task.iconId),
                color: AppPalette.deepGreen,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: status == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    '${s.timeLabel} · ${status == 'pending' && date.isBefore(dateOnly(DateTime.now())) ? 'Overdue' : status}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppPalette.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (!readOnly)
              PopupMenuButton<String>(
                tooltip: 'Change completion',
                initialValue: status,
                onSelected: (value) async {
                  try {
                    await HabitBackend.instance.mark(
                      targetUid: uid,
                      task: task,
                      date: date,
                      status: value,
                      previous: status,
                    );
                  } catch (e) {
                    if (context.mounted) toast(context, friendlyError(e));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'completed', child: Text('Complete')),
                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                  PopupMenuItem(value: 'skipped', child: Text('Skip')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    status == 'completed'
                        ? Icons.check_circle_rounded
                        : status == 'skipped'
                        ? Icons.remove_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: status == 'completed'
                        ? AppPalette.green
                        : AppPalette.muted,
                  ),
                ),
              )
            else
              Icon(
                status == 'completed'
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: status == 'completed'
                    ? AppPalette.green
                    : AppPalette.muted,
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 19),
                tooltip: 'Edit task settings',
                onPressed: onEdit,
              ),
          ],
        ),
      ),
    );
    return TaskCompletionFade(completed: status == 'completed', child: row);
  }
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({
    super.key,
    required this.uid,
    required this.editable,
    this.adminMode = false,
  });
  final String uid;
  final bool editable;
  final bool adminMode;
  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  String filter = 'All';
  void edit(HabitTask? task, {Object? addTag}) {
    final tag = task == null ? addTag : ('task-icon', task.id);
    Navigator.of(context).push<void>(
      sharedRoute<void>(
        context,
        TaskEditor(uid: widget.uid, task: task, iconHeroTag: tag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => HabitLiveBuilder(
    builder: (tasks, entries) {
      final day = DateTime.now();
      final statuses = {
        for (final entry in entries) (entry.taskId, entry.date): entry.status,
      };
      final matching = tasks.where((t) {
        if (t.isDeleted) return false;
        final s = t.latest;
        if (t.isArchived) return filter == 'Archived';
        if (filter == 'Archived') return false;
        if (filter == 'Recurring') return s.kind == 'recurring';
        if (filter == 'One-time') return s.kind == 'oneTime';
        return true;
      });
      final active = orderTasksForList(matching, day);
      final todayKey = dayKey(day);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(19, 22, 19, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.adminMode ? 'Tasks' : 'My Tasks',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SharedIcon(
                          tag: addTaskHeroTag,
                          icon: Icons.add_rounded,
                          child: RoundAction(
                            icon: Icons.add_rounded,
                            tooltip: 'Add task',
                            onPressed: () => edit(null, addTag: addTaskHeroTag),
                            background: AppPalette.mint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in [
                            'All',
                            'Recurring',
                            'One-time',
                            'Archived',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                label: Text(f),
                                selected: filter == f,
                                selectedColor: AppPalette.mint,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => filter = f),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (active.isEmpty)
                      const SoftCard(
                        child: EmptyMessage(
                          title: 'No tasks yet',
                          subtitle: 'Create a habit you would like to keep.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 95),
              sliver: SliverList.builder(
                itemCount: active.length,
                itemBuilder: (context, index) {
                  final (task: task, occurrenceDate: occurrenceDate) =
                      active[index];
                  final s = task.latest;
                  final dateLabel = occurrenceDate == null
                      ? ''
                      : ' · ${DateFormat('EEE, d MMM').format(fromDay(occurrenceDate))}';
                  final pendingEdit =
                      task.on(day) != null &&
                      s.effectiveFrom.compareTo(todayKey) > 0;
                  final completionDate = task.completionDate(day);
                  final status = completionDate == null
                      ? 'pending'
                      : statuses[(task.id, dayKey(completionDate))] ??
                            'pending';
                  final row = Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftCard(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 10,
                      ),
                      child: Row(
                        children: [
                          SharedIcon(
                            tag: ('task-icon', task.id),
                            icon: taskIcon(
                              s.name,
                              s.category,
                              iconId: task.iconId,
                            ),
                            child: CircleAvatar(
                              backgroundColor: taskCategoryColor(s.category),
                              child: Icon(
                                taskIcon(
                                  s.name,
                                  s.category,
                                  iconId: task.iconId,
                                ),
                                color: AppPalette.deepGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${s.kind == 'recurring' ? 'Recurring' : 'One-time'}$dateLabel · ${s.timeLabel}'
                                  '${s.paused ? ' · Paused' : ''}${task.isArchived ? ' · Archived' : ''}',
                                  maxLines: 2,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.muted,
                                  ),
                                ),
                                if (pendingEdit && !task.isArchived)
                                  Text(
                                    'Changes apply ${DateFormat('d MMM').format(fromDay(s.effectiveFrom))}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppPalette.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (completionDate != null && !widget.adminMode)
                            IconButton(
                              tooltip: 'Change completion status',
                              icon: MotionSwitcher(
                                child: Icon(
                                  status == 'completed'
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  key: ValueKey(status == 'completed'),
                                  color: status == 'completed'
                                      ? AppPalette.green
                                      : AppPalette.muted,
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  await HabitBackend.instance.mark(
                                    targetUid: widget.uid,
                                    task: task,
                                    date: completionDate,
                                    previous: status,
                                    status: status == 'completed'
                                        ? 'pending'
                                        : 'completed',
                                  );
                                } catch (e) {
                                  if (context.mounted)
                                    toast(context, friendlyError(e));
                                }
                              },
                            ),
                          if (widget.editable)
                            IconButton(
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 21,
                              ),
                              tooltip: 'Edit task',
                              onPressed: () => edit(task),
                            ),
                        ],
                      ),
                    ),
                  );
                  return TaskCompletionFade(
                    key: ValueKey(task.id),
                    completed: status == 'completed',
                    child: row,
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: () => edit(null, addTag: addTaskFabHeroTag),
          backgroundColor: AppPalette.green,
          foregroundColor: Colors.white,
          label: const Text('Add task'),
          icon: const SharedIcon(
            tag: addTaskFabHeroTag,
            icon: Icons.add_rounded,
            child: Icon(Icons.add_rounded),
          ),
        ),
      );
    },
  );
}

class _CalendarPage extends StatelessWidget {
  const _CalendarPage({required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => HabitLiveBuilder(
    builder: (tasks, entries) => ListView(
      padding: const EdgeInsets.fromLTRB(19, 23, 19, 40),
      children: [
        const Text(
          'Your Calendar',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          'Every day tells a story.',
          style: TextStyle(color: AppPalette.muted),
        ),
        const SizedBox(height: 20),
        CalendarBoard(uid: uid, tasks: tasks, entries: entries),
        const SizedBox(height: 12),
        const Text(
          'Tap a date to review or update its tasks.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppPalette.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

int currentStreak(List<HabitTask> tasks, List<HabitEntry> entries) {
  String? firstCompletion;
  for (final entry in entries) {
    if (entry.status == 'completed' &&
        (firstCompletion == null ||
            entry.date.compareTo(firstCompletion) < 0)) {
      firstCompletion = entry.date;
    }
  }
  if (firstCompletion == null || tasks.isEmpty) return 0;

  var streak = 0;
  final byDate = groupEntriesByDate(entries);
  final now = dateOnly(DateTime.now());
  for (int i = 0; i < 3650; i++) {
    final d = DateUtils.addDaysToDate(now, -i);
    final key = dayKey(d);
    if (key.compareTo(firstCompletion) < 0) break;
    final p = progressFor(d, tasks, byDate[key] ?? const []);
    if (p.total == 0) continue;
    if (p.done != p.total) {
      if (i == 0) continue; // Today need not be finished yet.
      break;
    }
    streak++;
  }
  return streak;
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => HabitLiveBuilder(
    builder: (tasks, entries) {
      final today = dateOnly(DateTime.now());
      final byDate = groupEntriesByDate(entries);
      var total = 0, done = 0, skipped = 0;
      var week = const DayProgress(0, 0, 0);
      for (var i = 0; i < 30; i++) {
        final date = DateUtils.addDaysToDate(today, -i);
        final progress = progressFor(
          date,
          tasks,
          byDate[dayKey(date)] ?? const [],
        );
        total += progress.total;
        done += progress.done;
        skipped += progress.skipped;
        if (i == 6) week = DayProgress(total, done, skipped);
      }
      final month = DayProgress(total, done, skipped);
      return ListView(
        padding: const EdgeInsets.all(19),
        children: [
          const Text(
            'Your Insights',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Little wins add up.',
            style: TextStyle(color: AppPalette.muted),
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: SoftCard(
                  color: AppPalette.mint,
                  child: Column(
                    children: [
                      ProgressRing(
                        progress: week.fraction,
                        center: '${(week.fraction * 100).round()}%',
                        subtitle: 'last 7 days',
                        size: 113,
                        stroke: 10,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${week.done}/${week.total} completed',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SoftCard(
                  color: AppPalette.lavender,
                  child: Column(
                    children: [
                      ProgressRing(
                        progress: month.fraction,
                        center: '${(month.fraction * 100).round()}%',
                        subtitle: 'last 30 days',
                        color: AppPalette.purple,
                        size: 113,
                        stroke: 10,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${month.done}/${month.total} completed',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          SoftCard(
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppPalette.red,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${currentStreak(tasks, entries)} consecutive scheduled days',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Last 7 days',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final day = today.subtract(Duration(days: 6 - i));
                final p = progressFor(day, tasks, entries);
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${(p.fraction * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppPalette.muted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 103,
                        alignment: Alignment.bottomCenter,
                        decoration: BoxDecoration(
                          color: AppPalette.mint,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: FractionallySizedBox(
                          heightFactor: p.fraction == 0 ? .02 : p.fraction,
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppPalette.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        DateFormat('E').format(day).substring(0, 1),
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${month.skipped} explicitly skipped in the last 30 days.',
            style: const TextStyle(color: AppPalette.muted, fontSize: 12),
          ),
        ],
      );
    },
  );
}
