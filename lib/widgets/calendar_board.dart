import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../core/palette.dart';
import '../models/habit.dart';
import '../services/habit_backend.dart';
import 'common.dart';
import 'task_icons.dart';
import 'motion_switcher.dart';

class CalendarBoard extends StatefulWidget {
  const CalendarBoard({
    super.key,
    required this.uid,
    required this.tasks,
    required this.entries,
    this.editable = true,
    this.initialMonth,
  });
  final String uid;
  final List<HabitTask> tasks;
  final List<HabitEntry> entries;
  final bool editable;
  final DateTime? initialMonth;
  @override
  State<CalendarBoard> createState() => _CalendarBoardState();
}

class _CalendarBoardState extends State<CalendarBoard> {
  late DateTime focused = DateTime(
    (widget.initialMonth ?? DateTime.now()).year,
    (widget.initialMonth ?? DateTime.now()).month,
  );
  late var _entriesByDate = groupEntriesByDate(widget.entries);

  @override
  void didUpdateWidget(CalendarBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries != oldWidget.entries) {
      _entriesByDate = groupEntriesByDate(widget.entries);
    }
  }

  void changeMonth(int delta) =>
      setState(() => focused = DateUtils.addMonthsToMonthDate(focused, delta));
  Future<void> chooseMonth() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: focused,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Choose month and year',
    );
    if (chosen != null && mounted) {
      setState(() => focused = DateTime(chosen.year, chosen.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(focused.year, focused.month);
    final offset = monthStart.weekday - 1;
    final days = DateUtils.getDaysInMonth(focused.year, focused.month);
    final count = ((offset + days) / 7).ceil() * 7;
    final todayDate = dateOnly(DateTime.now());
    final dateLabel = DateFormat('EEE d MMM');
    final monthEntries = _entriesByDate;
    return SoftCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: chooseMonth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(focused),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ),
              RoundAction(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onPressed: () => changeMonth(-1),
              ),
              const SizedBox(width: 3),
              RoundAction(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onPressed: () => changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (s) => Expanded(
                    child: Center(
                      child: Text(
                        s,
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 7),
          MotionSwitcher(
            child: GridView.builder(
              key: ValueKey(monthStart),
              itemCount: count,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 3,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, i) {
                final number = i - offset + 1;
                if (number <= 0 || number > days)
                  return const SizedBox.shrink();
                final day = DateTime(monthStart.year, monthStart.month, number);
                final p = progressFor(
                  day,
                  widget.tasks,
                  monthEntries[dayKey(day)] ?? const [],
                );
                final today = day == todayDate;
                final isPast = day.isBefore(todayDate);
                final Color color = p.total == 0
                    ? AppPalette.border
                    : p.done == p.total
                    ? AppPalette.green
                    : p.done > 0
                    ? AppPalette.amber
                    : (isPast ? AppPalette.red : AppPalette.border);
                return Tooltip(
                  message:
                      '${dateLabel.format(day)} · ${p.done}/${p.total} completed',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: () => showDayDetail(
                      context,
                      uid: widget.uid,
                      date: day,
                      tasks: widget.tasks,
                      entries: widget.entries,
                      editable: widget.editable,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: CustomPaint(
                          painter: _CalendarRingPainter(
                            progress: p.fraction,
                            color: color,
                            empty: p.total == 0,
                            isPending: p.done == 0 && p.total > 0 && isPast,
                          ),
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: today
                                    ? AppPalette.mint
                                    : Colors.transparent,
                              ),
                              child: Text(
                                '$number',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: today
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : AppPalette.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 13),
          const Wrap(
            spacing: 13,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              _LegendDot(AppPalette.green, 'Complete'),
              _LegendDot(AppPalette.amber, 'Partial'),
              _LegendDot(AppPalette.red, 'Pending / overdue'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarRingPainter extends CustomPainter {
  const _CalendarRingPainter({
    required this.progress,
    required this.color,
    required this.empty,
    required this.isPending,
  });
  final double progress;
  final Color color;
  final bool empty, isPending;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    final track = Paint()
      ..color = (empty ? AppPalette.border : color.withValues(alpha: .20))
      ..strokeWidth = 2.7
      ..style = PaintingStyle.stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, track);
    if (progress > 0 || isPending) {
      canvas.drawArc(
        r,
        -math.pi / 2,
        progress == 0 ? math.pi * 2 : math.pi * 2 * progress,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 2.7
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CalendarRingPainter other) =>
      other.progress != progress ||
      other.color != color ||
      other.empty != empty ||
      other.isPending != isPending;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 10, color: AppPalette.muted),
      ),
    ],
  );
}

void showDayDetail(
  BuildContext context, {
  required String uid,
  required DateTime date,
  required List<HabitTask> tasks,
  required List<HabitEntry> entries,
  required bool editable,
}) {
  final key = dayKey(date);
  final dayEntries = HabitBackend.instance.entries(uid, date: key);
  showModalBottomSheet<void>(
    sheetAnimationStyle: appOverlayMotion(context),
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .88,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 16, 21, 10),
          child: Column(
            children: [
              Container(
                width: 43,
                height: 5,
                decoration: BoxDecoration(
                  color: AppPalette.border,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('EEEE, d MMM yyyy').format(date),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 17),
              _DaySheetContent(
                uid: uid,
                date: date,
                tasks: tasks,
                entryStream: dayEntries,
                initialEntries: entries
                    .where((entry) => entry.date == key)
                    .toList(),
                editable: editable,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DaySheetContent extends StatelessWidget {
  const _DaySheetContent({
    required this.uid,
    required this.date,
    required this.tasks,
    required this.initialEntries,
    required this.entryStream,
    required this.editable,
  });
  final String uid;
  final DateTime date;
  final List<HabitTask> tasks;
  final List<HabitEntry> initialEntries;
  final Stream<List<HabitEntry>> entryStream;
  final bool editable;
  @override
  Widget build(BuildContext context) => Expanded(
    child: StreamBuilder<List<HabitEntry>>(
      stream: entryStream,
      initialData: initialEntries,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? initialEntries;
        final current = tasks.where((t) => t.scheduled(date)).toList();
        final p = progressFor(date, tasks, entries);
        return Column(
          children: [
            SoftCard(
              color: AppPalette.mint,
              child: Row(
                children: [
                  ProgressRing(
                    progress: p.fraction,
                    center: '${p.done}/${p.total}',
                    subtitle: 'completed',
                    size: 115,
                    stroke: 10,
                  ),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(p.fraction * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.deepGreen,
                          ),
                        ),
                        const Text(
                          'of scheduled habits',
                          style: TextStyle(color: AppPalette.deepGreen),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${p.pending} pending · ${p.skipped} skipped',
                          style: const TextStyle(
                            color: AppPalette.deepGreen,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: current.isEmpty
                  ? const EmptyMessage(
                      title: 'No tasks this day',
                      subtitle: 'A little breathing room!',
                    )
                  : ListView.separated(
                      itemCount: current.length,
                      separatorBuilder: (context, i) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final task = current[i];
                        final version = task.on(date)!;
                        final status = statusFor(task.id, date, entries);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 3,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: taskCategoryColor(
                              version.category,
                            ),
                            child: Icon(
                              status == 'completed'
                                  ? Icons.check_rounded
                                  : status == 'skipped'
                                  ? Icons.remove_rounded
                                  : taskIcon(
                                      version.name,
                                      version.category,
                                      iconId: task.iconId,
                                    ),
                              color: AppPalette.deepGreen,
                            ),
                          ),
                          title: Text(
                            version.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${version.timeLabel} · ${status.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppPalette.muted,
                            ),
                          ),
                          trailing: editable
                              ? PopupMenuButton<String>(
                                  tooltip: 'Change task status',
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
                                      if (context.mounted)
                                        toast(context, friendlyError(e));
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'completed',
                                      child: Text('Mark completed'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'pending',
                                      child: Text('Mark pending'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'skipped',
                                      child: Text('Skip task'),
                                    ),
                                  ],
                                )
                              : Icon(
                                  status == 'completed'
                                      ? Icons.check_circle_rounded
                                      : Icons.circle_outlined,
                                  color: status == 'completed'
                                      ? AppPalette.green
                                      : AppPalette.muted,
                                ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
