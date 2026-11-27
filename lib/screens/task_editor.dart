import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../core/palette.dart';
import '../models/habit.dart';
import '../services/habit_backend.dart';
import '../widgets/common.dart';
import '../widgets/task_icons.dart';
import '../widgets/task_icon_picker.dart';
import '../widgets/motion_switcher.dart';
import '../widgets/shared_element.dart';

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.uid, this.task, this.iconHeroTag});
  final String uid;
  final HabitTask? task;
  final Object? iconHeroTag;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), description = TextEditingController();
  String kind = 'recurring', category = 'Personal';
  late String startDate, oneTimeDate;
  String? endDate;
  List<int> weekdays = [1, 2, 3, 4, 5, 6, 7];
  int? timeMinutes;
  String? iconId;
  bool savingIcon = false;
  bool reminders = true, paused = false, archived = false, busy = false;
  int lead = 2, interval = 2;
  bool get editing => widget.task != null;
  @override
  void initState() {
    super.initState();
    startDate = dayKey(DateTime.now());
    oneTimeDate = startDate;
    if (!editing) {
      _loadDefaults();
    }
    if (editing) {
      final s = widget.task!.latest;
      name.text = s.name;
      iconId = widget.task!.iconId;
      description.text = s.description;
      kind = s.kind;
      category = s.category;
      startDate = s.startDate;
      oneTimeDate = s.oneTimeDate ?? startDate;
      endDate = s.endDate;
      weekdays = [...s.weekdays];
      timeMinutes = s.timeMinutes;
      reminders = s.remindersEnabled;
      lead = s.leadMinutes;
      interval = s.repeatMinutes;
      paused = s.paused;
      archived = s.archived;
    }
  }

  Future<void> _loadDefaults() async {
    try {
      final snap = await HabitBackend.instance.preferences(widget.uid).first;
      if (!mounted) return;
      final prefs = snap.data() ?? <String, dynamic>{};
      setState(() {
        lead = prefs['defaultLeadMinutes'] as int? ?? 2;
        interval = prefs['defaultRepeatMinutes'] as int? ?? 2;
      });
    } catch (_) {
      /* Defaults remain 2 minutes until configured. */
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pickDate({required String which}) async {
    final initial = which == 'oneTime'
        ? oneTimeDate
        : which == 'end'
        ? (endDate ?? dayKey(DateTime.now().add(const Duration(days: 30))))
        : startDate;
    final first = DateTime(2020), last = DateTime(2100);
    final date = await showDatePicker(
      context: context,
      initialDate: fromDay(initial),
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || date == null) return;
    setState(() {
      if (which == 'oneTime') {
        oneTimeDate = dayKey(date);
      } else if (which == 'end') {
        endDate = dayKey(date);
      } else {
        startDate = dayKey(date);
      }
    });
  }

  Future<void> pickTime() async {
    final initial = TimeOfDay(
      hour: (timeMinutes ?? 7 * 60) ~/ 60,
      minute: (timeMinutes ?? 7 * 60) % 60,
    );
    final chosen = await showTimePicker(context: context, initialTime: initial);
    if (!mounted || chosen == null) return;
    setState(() => timeMinutes = chosen.hour * 60 + chosen.minute);
  }

  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (kind == 'recurring' && weekdays.isEmpty) {
      toast(context, 'Select at least one weekday.');
      return;
    }
    if (kind == 'recurring' &&
        endDate != null &&
        endDate!.compareTo(startDate) < 0) {
      toast(context, 'End date must be on or after the start date.');
      return;
    }
    setState(() => busy = true);
    try {
      final schedule = HabitSchedule(
        effectiveFrom: dayKey(DateTime.now()),
        name: name.text.trim(),
        description: description.text.trim(),
        category: category,
        kind: kind,
        startDate: startDate,
        oneTimeDate: kind == 'oneTime' ? oneTimeDate : null,
        endDate: kind == 'recurring' ? endDate : null,
        weekdays: kind == 'recurring' ? weekdays : const [],
        timeMinutes: timeMinutes,
        remindersEnabled: reminders && timeMinutes != null,
        leadMinutes: lead,
        repeatMinutes: interval,
        paused: paused,
        archived: archived,
      );
      final movedToToday =
          editing &&
          kind == 'oneTime' &&
          widget.task!.latest.oneTimeDate != oneTimeDate &&
          oneTimeDate == dayKey(DateTime.now());
      await HabitBackend.instance.saveTask(
        targetUid: widget.uid,
        taskId: widget.task?.id,
        expectedVersionCount: widget.task?.versions.length,
        iconId: iconId,
        definition: schedule,
      );
      if (!mounted) return;
      toast(
        context,
        editing
            ? (archived
                  ? 'Task archived.'
                  : movedToToday
                  ? 'Task moved to today.'
                  : 'Changes saved.')
            : 'Habit created!',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteTask() async {
    final task = widget.task!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(
          '“${task.latest.name}” will be removed from your tasks and reminders. '
          'Past records will stay in your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete task'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => busy = true);
    try {
      await HabitBackend.instance.deleteTask(widget.uid, task.id);
      if (!mounted) return;
      toast(context, 'Task deleted.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseIcon() async {
    final choice = await Navigator.of(context).push<String>(
      sharedRoute<String>(
        context,
        TaskIconPicker(
          selectedId: iconId,
          previewIcon: taskIcon(name.text, category, iconId: iconId),
          iconHeroTag: widget.iconHeroTag,
        ),
        overlay: true,
      ),
    );
    if (!mounted || choice == null) return;
    final selected = choice == 'auto' ? null : choice;
    if (selected == iconId) return;
    if (!editing) {
      setState(() => iconId = selected);
      return;
    }
    setState(() => savingIcon = true);
    try {
      await HabitBackend.instance.setTaskIcon(
        targetUid: widget.uid,
        taskId: widget.task!.id,
        iconId: selected,
      );
      if (mounted) setState(() => iconId = selected);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => savingIcon = false);
    }
  }

  Widget fieldTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        editing ? 'Edit Task' : 'Add Task',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        if (editing)
          IconButton(
            onPressed: busy || savingIcon ? null : deleteTask,
            tooltip: 'Delete task',
            color: Theme.of(context).colorScheme.error,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(19, 10, 19, 35),
        children: [
          Center(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: name,
              builder: (context, value, child) {
                final icon = taskIcon(value.text, category, iconId: iconId);
                final button = IconButton(
                  tooltip: 'Change task icon',
                  onPressed: busy || savingIcon ? null : chooseIcon,
                  iconSize: 40,
                  padding: const EdgeInsets.all(20),
                  style: IconButton.styleFrom(
                    backgroundColor: taskCategoryColor(category),
                    foregroundColor: AppPalette.deepGreen,
                  ),
                  icon: Icon(icon),
                );
                final tag = widget.iconHeroTag;
                return tag == null
                    ? button
                    : SharedIcon(tag: tag, icon: icon, child: button);
              },
            ),
          ),
          const SizedBox(height: 20),
          fieldTitle('Task name *'),
          TextFormField(
            controller: name,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: 'e.g. Morning Exercise',
              counterText: '',
            ),
            validator: (s) =>
                s == null || s.trim().isEmpty ? 'A task needs a name' : null,
          ),
          const SizedBox(height: 16),
          fieldTitle('Description (optional)'),
          TextFormField(
            controller: description,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'What would you like to do?',
            ),
          ),
          const SizedBox(height: 10),
          fieldTitle('Category'),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(),
            items: [
              'Personal',
              'Health',
              'Study',
              'Work',
              'Mindfulness',
            ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => category = v);
            },
          ),
          const SizedBox(height: 22),
          fieldTitle('Task type'),
          Row(
            children: [
              Expanded(
                child: _SelectTile(
                  'One-time',
                  Icons.event_available_rounded,
                  selected: kind == 'oneTime',
                  onTap: () => setState(() => kind = 'oneTime'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _SelectTile(
                  'Recurring',
                  Icons.repeat_rounded,
                  selected: kind == 'recurring',
                  onTap: () => setState(() => kind = 'recurring'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (kind == 'oneTime') ...[
            fieldTitle('Scheduled date'),
            OutlinedButton.icon(
              onPressed: () => pickDate(which: 'oneTime'),
              icon: const Icon(Icons.event_rounded),
              label: Text(
                DateFormat('EEE, d MMM yyyy').format(fromDay(oneTimeDate)),
              ),
            ),
          ] else ...[
            fieldTitle('Repeat on'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final day = i + 1, selected = weekdays.contains(day);
                return InkWell(
                  onTap: () => setState(
                    () => selected ? weekdays.remove(day) : weekdays.add(day),
                  ),
                  borderRadius: BorderRadius.circular(50),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: selected
                        ? AppPalette.green
                        : AppPalette.mint,
                    child: Text(
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppPalette.deepGreen,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pickDate(which: 'start'),
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(
                      'From ${DateFormat('d MMM yy').format(fromDay(startDate))}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => pickDate(which: 'end'),
                    icon: const Icon(Icons.event_busy_outlined, size: 15),
                    label: Text(
                      endDate == null
                          ? 'No end date'
                          : 'To ${DateFormat('d MMM yy').format(fromDay(endDate!))}',
                    ),
                  ),
                ),
              ],
            ),
            if (endDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => endDate = null),
                  child: const Text('Remove end date'),
                ),
              ),
          ],
          const SizedBox(height: 18),
          fieldTitle('Time (optional)'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: pickTime,
                  icon: const Icon(Icons.access_time_rounded),
                  label: Text(
                    timeMinutes == null
                        ? 'Set a time'
                        : TimeOfDay(
                            hour: timeMinutes! ~/ 60,
                            minute: timeMinutes! % 60,
                          ).format(context),
                  ),
                ),
              ),
              if (timeMinutes != null)
                IconButton(
                  tooltip: 'Clear time',
                  onPressed: () => setState(() {
                    timeMinutes = null;
                    reminders = false;
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SoftCard(
            color: AppPalette.mint,
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Reminders',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text(
                    'Repeat until completed or skipped.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: reminders && timeMinutes != null,
                  onChanged: timeMinutes == null
                      ? null
                      : (v) => setState(() => reminders = v),
                ),
                if (reminders && timeMinutes != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Remind before',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownButton<int>(
                        value: lead,
                        underline: const SizedBox(),
                        items: [0, 1, 2, 5, 10, 15, 30, 60]
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n min'),
                              ),
                            )
                            .toList(),
                        onChanged: (n) {
                          if (n != null) setState(() => lead = n);
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Repeat every',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownButton<int>(
                        value: interval,
                        underline: const SizedBox(),
                        items: [1, 2, 3, 5, 10, 15, 30, 60]
                            .map(
                              (n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n min'),
                              ),
                            )
                            .toList(),
                        onChanged: (n) {
                          if (n != null) setState(() => interval = n);
                        },
                      ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Reminders are best-effort and may be delayed by Android or iOS.',
                      style: TextStyle(color: AppPalette.muted, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (editing) ...[
            if (widget.uid == HabitBackend.instance.uid &&
                timeMinutes != null) ...[
              const SizedBox(height: 13),
              OutlinedButton.icon(
                icon: const Icon(Icons.snooze_rounded),
                label: const Text('Snooze reminders'),
                onPressed: () async {
                  final minutes = await showModalBottomSheet<int>(
                    sheetAnimationStyle: appOverlayMotion(context),
                    context: context,
                    builder: (sheet) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 15),
                          const Text(
                            'Snooze for',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          for (final n in [5, 10, 30, 60])
                            ListTile(
                              title: Text('$n minutes'),
                              onTap: () => Navigator.pop(sheet, n),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (minutes == null) return;
                  try {
                    await HabitBackend.instance.snooze(
                      widget.uid,
                      widget.task!.id,
                      minutes,
                    );
                    if (context.mounted)
                      toast(context, 'Reminders snoozed for $minutes minutes.');
                  } catch (e) {
                    if (context.mounted) toast(context, friendlyError(e));
                  }
                },
              ),
            ],
            const SizedBox(height: 17),
            SwitchListTile(
              title: const Text('Pause task'),
              value: paused,
              subtitle: const Text(
                'Stops scheduling new occurrences and reminders.',
              ),
              onChanged: (v) => setState(() => paused = v),
            ),
            SwitchListTile(
              title: const Text('Archive task'),
              value: archived,
              subtitle: const Text(
                'Moves it to Archived when saved. Keeps past records.',
              ),
              onChanged: (v) => setState(() => archived = v),
            ),
            const SizedBox(height: 10),
            const Text(
              'Schedule changes apply immediately. Completed and skipped records are kept.',
              style: TextStyle(fontSize: 11, color: AppPalette.muted),
            ),
          ],
          const SizedBox(height: 27),
          PrimaryButton(
            label: editing ? 'Save Changes' : 'Create Task',
            icon: Icons.check_rounded,
            busy: busy,
            onPressed: save,
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: busy || savingIcon ? null : deleteTask,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete task'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SelectTile extends StatelessWidget {
  const _SelectTile(
    this.label,
    this.icon, {
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppPalette.mint : Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppPalette.green : AppPalette.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppPalette.deepGreen : AppPalette.muted,
              size: 18,
            ),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}
