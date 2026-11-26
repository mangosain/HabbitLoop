import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/habit.dart';
import 'habit_backend.dart';

/// Spark edition: all reminders are device-local, never cloud-sent.
/// Schedules a rolling lookahead of up to 54 reminders (iOS keeps at most 64).
/// Older pending occurrences share ONE stream per task. Rebuild on data changes,
/// launch and foreground. OS policies can delay alarms; a fully closed app can't
/// refresh schedules in response to remote edits/completions.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final instance = NotificationService._();
  final notifications = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _uid;
  bool _rescheduling = false;
  bool _reloadAgain = false;
  Timer? _debounce;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  List<HabitTask>? _tasks;
  Set<String> _archivedTaskIds = {};
  List<HabitEntry>? _entries;
  Map<String, dynamic>? _prefs;
  Map<String, DateTime> _snoozes = {};
  bool _snoozesLoaded = false;

  Future<String> deviceTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    final name = await deviceTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'habitloop_reminders',
            'Habit reminders',
            description: 'Reminders for incomplete habits',
            importance: Importance.high,
          ),
        );
    _ready = true;
  }

  Future<void> attachUser(String uid) async {
    await initialize();
    if (_uid == uid) return;
    await detachUser();
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final db = FirebaseFirestore.instance.collection('users').doc(uid);
    _subscriptions.add(
      HabitBackend.instance.tasks(uid).listen((tasks) {
        final archived = {
          for (final task in tasks)
            if (task.isArchived || task.isDeleted) task.id,
        };
        final newlyArchived = archived.difference(_archivedTaskIds).isNotEmpty;
        _tasks = tasks;
        _archivedTaskIds = archived;
        if (newlyArchived) {
          _debounce?.cancel();
          unawaited(_reschedule());
        } else {
          _queueRebuild();
        }
      }),
    );
    _subscriptions.add(
      HabitBackend.instance.entries(uid).listen((entries) {
        _entries = entries;
        _queueRebuild();
      }),
    );
    _subscriptions.add(
      HabitBackend.instance.preferences(uid).listen((snapshot) {
        _prefs = snapshot.data() ?? {};
        _queueRebuild();
      }),
    );
    _subscriptions.add(
      db.collection('reminderStates').snapshots().listen((snapshot) {
        _snoozes = {
          for (final doc in snapshot.docs)
            if (doc.data()['snoozeUntil'] is Timestamp)
              doc.id: (doc.data()['snoozeUntil'] as Timestamp).toDate(),
        };
        _snoozesLoaded = true;
        _queueRebuild();
      }),
    );
  }

  void _queueRebuild() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_reschedule());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshTimezoneAndSchedule());
    }
  }

  Future<void> _refreshTimezoneAndSchedule() async {
    final name = await deviceTimezone();
    try {
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      /* retain */
    }
    _queueRebuild();
  }

  bool _quiet(DateTime time, Map<String, dynamic> pref) {
    if (pref['quietHoursEnabled'] != true) return false;
    final s = pref['quietStart'] as int? ?? 1320;
    final e = pref['quietEnd'] as int? ?? 420;
    final at = time.hour * 60 + time.minute;
    if (s == e) return false;
    return s < e ? at >= s && at < e : at >= s || at < e;
  }

  /// Number of due, still-pending dated occurrences for this task; next trigger
  /// is the first non-quiet moment on or after the oldest outstanding due time.
  ({int count, DateTime? firstDue}) _outstanding(
    HabitTask task,
    Map<String, String> statuses,
    DateTime now,
    HabitSchedule current,
  ) {
    final first = task.versions.first.effectiveFrom;
    final oneTimeDate = current.kind == 'oneTime' ? current.oneTimeDate : null;
    final start = fromDay(
      oneTimeDate != null && oneTimeDate.compareTo(first) > 0
          ? oneTimeDate
          : first,
    );
    if (start.isAfter(DateTime(now.year, now.month, now.day + 8))) {
      return (count: 0, firstDue: null);
    }
    final last = DateTime(now.year, now.month, now.day + 7);
    final horizon = now.add(const Duration(days: 7));
    var count = 0;
    DateTime? earliest;
    for (
      var day = start, n = 0;
      !day.isAfter(last) && n < 15000;
      day = DateTime(day.year, day.month, day.day + 1), n++
    ) {
      final key = dayKey(day);
      final schedule = task.occurrenceOn(day, dateKey: key);
      final minute = schedule?.timeMinutes;
      if (schedule == null || minute == null || !schedule.remindersEnabled)
        continue;
      final status = statuses['${task.id}_$key'];
      if (status == 'completed' || status == 'skipped') continue;
      final due = DateTime(
        day.year,
        day.month,
        day.day,
        minute ~/ 60,
        minute % 60,
      ).subtract(Duration(minutes: schedule.leadMinutes));
      if (due.isAfter(horizon)) continue;
      if (!due.isAfter(now)) count++;
      if (earliest == null || due.isBefore(earliest)) earliest = due;
    }
    // Future due occurrence only: one stream starts at that first due instant.
    return (count: count, firstDue: earliest);
  }

  Future<void> _reschedule() async {
    if (_uid == null ||
        _tasks == null ||
        _entries == null ||
        _prefs == null ||
        !_snoozesLoaded) {
      return;
    }
    if (_rescheduling) {
      _reloadAgain = true;
      return;
    }
    _rescheduling = true;
    final activeUid = _uid;
    try {
      // Never leave reminders for another user after switching accounts.
      final pending = await notifications.pendingNotificationRequests();
      for (final item in pending) {
        await notifications.cancel(id: item.id);
      }
      if (_prefs!['notificationsEnabled'] == false || activeUid != _uid) return;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 7));
      final statuses = {
        for (final e in _entries!) '${e.taskId}_${e.date}': e.status,
      };
      final candidates =
          <({DateTime at, String taskId, String name, int outstanding})>[];
      for (final task in _tasks!) {
        final current = task.reminderScheduleAt(now);
        if (current == null) continue;
        final due = _outstanding(task, statuses, now, current);
        if (due.firstDue == null) continue;
        final interval = current.repeatMinutes.clamp(1, 1440);
        var next = due.firstDue!.isAfter(now)
            ? due.firstDue!
            : now.add(const Duration(seconds: 35));
        final snooze = _snoozes[task.id];
        if (snooze != null && snooze.isAfter(next)) next = snooze;
        // No hard total duration; a rolling window is refreshed when the app
        // wakes. OS restrictions prevent indefinite exact delivery while closed.
        var added = 0;
        for (
          var i = 0;
          i < 10080 && added < 54 && next.isBefore(horizon);
          i++
        ) {
          if (!_quiet(next, _prefs!)) {
            candidates.add((
              at: next,
              taskId: task.id,
              name: current.name,
              outstanding: due.count > 0 ? due.count : 1,
            ));
            added++;
          }
          next = next.add(Duration(minutes: interval));
        }
      }
      candidates.sort((a, b) => a.at.compareTo(b.at));
      var id = 800000;
      for (final item in candidates) {
        if (_uid != activeUid) return;
        if (id >= 800054) break;
        if (_archivedTaskIds.contains(item.taskId)) continue;
        final notificationId = id++;
        try {
          await notifications.zonedSchedule(
            id: notificationId,
            title: '${item.name} · HabitLoop',
            body: item.outstanding == 1
                ? 'A pending habit needs your attention.'
                : '${item.outstanding} pending occurrences need your attention.',
            scheduledDate: tz.TZDateTime.from(item.at, tz.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'habitloop_reminders',
                'Habit reminders',
                channelDescription: 'Reminders for incomplete habits',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: item.taskId,
          );
          if (_uid != activeUid || _archivedTaskIds.contains(item.taskId)) {
            await notifications.cancel(id: notificationId);
          }
        } catch (_) {
          /* Unsupported OS scheduling and permission failures. */
        }
      }
    } finally {
      _rescheduling = false;
      if (_reloadAgain) {
        _reloadAgain = false;
        _debounce?.cancel();
        unawaited(_reschedule());
      }
    }
  }

  Future<void> detachUser() async {
    _debounce?.cancel();
    _uid = null;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _tasks = null;
    _archivedTaskIds = {};
    _entries = null;
    _prefs = null;
    _snoozesLoaded = false;
    _snoozes = {};
    WidgetsBinding.instance.removeObserver(this);
    if (_ready) {
      final pending = await notifications.pendingNotificationRequests();
      for (final item in pending) {
        await notifications.cancel(id: item.id);
      }
    }
  }
}
