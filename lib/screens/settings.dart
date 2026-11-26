import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../services/habit_backend.dart';
import '../services/notifications.dart';
import '../widgets/common.dart';
import '../widgets/motion_switcher.dart';
import '../widgets/shared_element.dart';
import 'activity_history.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.uid,
    required this.isAdmin,
    this.animateReminders = false,
  });
  final String uid;
  final bool isAdmin;
  final bool animateReminders;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String get uid => widget.uid;
  bool get animateReminders => widget.animateReminders;

  late var _preferences = HabitBackend.instance.preferences(uid);

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != uid)
      _preferences = HabitBackend.instance.preferences(uid);
  }

  Future<void> update(BuildContext context, Map<String, dynamic> patch) async {
    try {
      await HabitBackend.instance.setPreference(uid, patch);
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    key: ValueKey(uid),
    stream: _preferences,
    builder: (context, snapshot) {
      final m = snapshot.data?.data() ?? <String, dynamic>{};
      final dark = m['darkMode'] == true;
      final enabled = m['notificationsEnabled'] != false;
      final quiet = m['quietHoursEnabled'] == true;
      final lead = m['defaultLeadMinutes'] as int? ?? 2;
      final repeat = m['defaultRepeatMinutes'] as int? ?? 2;
      final start = m['quietStart'] as int? ?? 1320;
      final end = m['quietEnd'] as int? ?? 420;
      Future<void> pickQuiet(String which) async {
        final min = which == 'start' ? start : end;
        final result = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: min ~/ 60, minute: min % 60),
        );
        if (result != null && context.mounted) {
          await update(context, {
            which == 'start' ? 'quietStart' : 'quietEnd':
                result.hour * 60 + result.minute,
          });
        }
      }

      return Scaffold(
        backgroundColor: animateReminders ? null : Colors.transparent,
        appBar: animateReminders ? AppBar(title: const Text('Settings')) : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(19, 22, 19, 35),
          children: [
            if (!animateReminders)
              const Text(
                'Settings',
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
              ),
            const SizedBox(height: 21),
            SoftCard(
              child: Column(
                children: [
                  _SectionTitle(
                    Icons.notifications_none_rounded,
                    'Reminders',
                    heroTag: animateReminders ? remindersHeroTag : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Notifications'),
                    subtitle: const Text('Reminders for tasks with a set time'),
                    value: enabled,
                    onChanged: (v) =>
                        update(context, {'notificationsEnabled': v}),
                  ),
                  _OptionsRow('Default first reminder', lead, [
                    0,
                    1,
                    2,
                    5,
                    10,
                    15,
                    30,
                    60,
                  ], (v) => update(context, {'defaultLeadMinutes': v})),
                  _OptionsRow('Default repeat interval', repeat, [
                    1,
                    2,
                    3,
                    5,
                    10,
                    15,
                    30,
                    60,
                  ], (v) => update(context, {'defaultRepeatMinutes': v})),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Quiet hours'),
                    subtitle: const Text(
                      'Pause notifications during your chosen hours',
                    ),
                    value: quiet,
                    onChanged: (v) => update(context, {'quietHoursEnabled': v}),
                  ),
                  if (quiet) ...[
                    ListTile(
                      title: const Text('Start'),
                      trailing: Text(
                        TimeOfDay(
                          hour: start ~/ 60,
                          minute: start % 60,
                        ).format(context),
                      ),
                      onTap: () => pickQuiet('start'),
                    ),
                    ListTile(
                      title: const Text('End'),
                      trailing: Text(
                        TimeOfDay(
                          hour: end ~/ 60,
                          minute: end % 60,
                        ).format(context),
                      ),
                      onTap: () => pickQuiet('end'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 13),
            SoftCard(
              child: Column(
                children: [
                  const _SectionTitle(Icons.palette_outlined, 'Appearance'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dark mode'),
                    value: dark,
                    onChanged: (v) => update(context, {'darkMode': v}),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            SoftCard(
              child: Column(
                children: [
                  const _SectionTitle(
                    Icons.manage_accounts_outlined,
                    'Account',
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Change password'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showDialog<void>(
                      animationStyle: appOverlayMotion(context),
                      context: context,
                      builder: (_) => const _ChangePasswordDialog(),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const SharedIcon(
                      tag: activityHeroTag,
                      icon: Icons.history_rounded,
                      child: Icon(Icons.history_rounded),
                    ),
                    title: const Text('Activity history'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      sharedRoute<void>(context, ActivityHistoryPage(uid: uid)),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sync_rounded),
                    title: const Text('Sync status'),
                    subtitle: Text(
                      snapshot.hasData && snapshot.data!.metadata.isFromCache
                          ? 'Viewing cached settings · waiting to sync'
                          : 'Connected to Firebase',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            SoftCard(
              child: const Column(
                children: [
                  _SectionTitle(Icons.info_outline_rounded, 'About'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('HabitLoop'),
                    subtitle: Text(
                      'A little progress, every day · Version 1.0',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 19),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await NotificationService.instance.detachUser();
                  await HabitBackend.instance.logout();
                } catch (e) {
                  if (context.mounted) toast(context, friendlyError(e));
                }
              },
              icon: const Icon(Icons.logout_rounded, color: AppPalette.red),
              label: const Text(
                'Sign out',
                style: TextStyle(color: AppPalette.red),
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              'Reminders are delivered on a best-effort basis. System notification settings and connectivity may affect them.',
              style: TextStyle(fontSize: 11, color: AppPalette.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.text, {this.heroTag});
  final Object? heroTag;
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (heroTag case final tag?)
        SharedIcon(
          tag: tag,
          icon: icon,
          child: Icon(icon, color: AppPalette.deepGreen),
        )
      else
        Icon(icon, color: AppPalette.deepGreen),
      const SizedBox(width: 10),
      Text(
        text,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _OptionsRow extends StatelessWidget {
  const _OptionsRow(this.label, this.value, this.items, this.onChange);
  final String label;
  final int value;
  final List<int> items;
  final void Function(int) onChange;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      DropdownButton<int>(
        value: items.contains(value) ? value : items.first,
        underline: const SizedBox(),
        items: items
            .map((n) => DropdownMenuItem(value: n, child: Text('$n min')))
            .toList(),
        onChanged: (v) {
          if (v != null) onChange(v);
        },
      ),
    ],
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final old = TextEditingController(), next = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (next.text.length < 10) {
      toast(context, 'Use at least 10 characters.');
      return;
    }
    setState(() => busy = true);
    try {
      await HabitBackend.instance.changePassword(old.text, next.text);
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'Password updated.');
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: old,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: next,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (10+ characters)',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: busy ? null : save, child: const Text('Update')),
    ],
  );
}
