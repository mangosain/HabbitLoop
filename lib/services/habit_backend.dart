import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/habit.dart';
import 'task_sync_queue.dart';

class HabitBackend {
  static final HabitBackend instance = HabitBackend._();
  HabitBackend._();
  final _queue = TaskSyncQueue();
  final _syncing = <String>{};
  final taskSyncIssue = ValueNotifier<String?>(null);
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String get uid => FirebaseAuth.instance.currentUser!.uid;
  String userEmail(String username) =>
      '${username.toLowerCase().trim()}@habitloop.example';

  Stream<DocumentSnapshot<Map<String, dynamic>>> profile(String targetUid) => db
      .collection('users')
      .doc(targetUid)
      .snapshots(includeMetadataChanges: true);
  Stream<List<HabitTask>> tasks(String targetUid) => Stream.multi((output) {
    List<HabitTask>? remote;
    var generation = 0;

    Future<void> publish() async {
      final snapshot = remote;
      if (snapshot == null) return;
      final request = ++generation;
      try {
        final changes = await _queue.read(targetUid);
        if (request != generation || output.isClosed) return;
        final tasks = {for (final task in snapshot) task.id: task};
        for (final change in changes) {
          final id = change['taskId'] as String;
          final task = tasks[id];
          final kind = change['kind'];
          if (kind == 'status') continue;
          if (kind == 'create' ? task != null : task == null || task.isDeleted)
            continue;
          if (task?.versions.any((version) => version.syncId == change['id']) ==
              true)
            continue;
          final definition = change['definition'] as Map<String, dynamic>?;
          final date = change['date'] as String;
          tasks[id] = HabitTask(
            id: id,
            versions: [
              ...?task?.versions,
              if (definition != null)
                HabitSchedule.fromMap({
                  ...?task?.latest.toDefinition(),
                  ...definition,
                  'effectiveFrom': date,
                }),
            ],
            iconId: change.containsKey('iconId')
                ? change['iconId'] as String?
                : task?.iconId,
            createdAt:
                task?.createdAt ??
                DateTime.tryParse(change['createdAt'] as String? ?? ''),
            deletedOn: kind == 'delete' ? date : task?.deletedOn,
          );
        }
        output.add(tasks.values.toList());
      } catch (error, stack) {
        if (!output.isClosed) output.addError(error, stack);
      }
    }

    final server =
        _watchCollection(
          db.collection('users').doc(targetUid).collection('tasks'),
          HabitTask.fromDoc,
        ).listen((tasks) {
          remote = tasks.where((task) => task.versions.isNotEmpty).toList();
          unawaited(publish());
          unawaited(_flushTaskChanges(targetUid));
        }, onError: output.addError);
    final local = _queue.changes.where((uid) => uid == targetUid).listen((_) {
      unawaited(publish());
    });
    final retry = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_flushTaskChanges(targetUid));
    });
    output.onCancel = () async {
      retry.cancel();
      await server.cancel();
      await local.cancel();
    };
  });

  Stream<List<HabitEntry>> entries(String targetUid, {String? date}) =>
      Stream.multi((output) {
        final collection = db
            .collection('users')
            .doc(targetUid)
            .collection('occurrences');
        final query = date == null
            ? collection
            : collection.where('date', isEqualTo: date);
        List<HabitEntry>? remote;
        var generation = 0;
        Future<void> publish() async {
          final snapshot = remote;
          if (snapshot == null) return;
          final request = ++generation;
          try {
            final changes = await _queue.read(targetUid);
            if (request != generation || output.isClosed) return;
            final entries = {
              for (final entry in snapshot) (entry.taskId, entry.date): entry,
            };
            for (final change in changes) {
              if (change['kind'] != 'status' ||
                  (date != null && change['occurrenceDate'] != date))
                continue;
              final entry = HabitEntry(
                change['taskId'] as String,
                change['occurrenceDate'] as String,
                change['status'] as String,
              );
              entries[(entry.taskId, entry.date)] = entry;
            }
            output.add(entries.values.toList());
          } catch (error, stack) {
            if (!output.isClosed) output.addError(error, stack);
          }
        }

        final server = _watchCollection(query, HabitEntry.fromDoc).listen((
          entries,
        ) {
          remote = entries;
          unawaited(publish());
        }, onError: output.addError);
        final local = _queue.changes.where((uid) => uid == targetUid).listen((
          _,
        ) {
          unawaited(publish());
        });
        output.onCancel = () async {
          await server.cancel();
          await local.cancel();
        };
      });

  Stream<List<T>> _watchCollection<T>(
    Query<Map<String, dynamic>> query,
    T Function(DocumentSnapshot<Map<String, dynamic>>) parse, {
    bool includeMetadataChanges = false,
  }) async* {
    final byId = <String, T>{};
    await for (final snapshot in query.snapshots(
      includeMetadataChanges: includeMetadataChanges,
    )) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) {
          byId.remove(change.doc.id);
        } else {
          byId[change.doc.id] = parse(change.doc);
        }
      }
      yield [
        for (final doc in snapshot.docs)
          byId.putIfAbsent(doc.id, () => parse(doc)),
      ];
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> preferences(
    String targetUid,
  ) => db
      .collection('users')
      .doc(targetUid)
      .collection('settings')
      .doc('preferences')
      .snapshots();

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final id = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,31}$').hasMatch(id)) {
      throw ArgumentError('Use a 3–32 character ID starting with a letter.');
    }
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: userEmail(id),
      password: password,
    );
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
    taskSyncIssue.value = null;
  }

  Future<void> discardBlockedTaskChange(String targetUid) async {
    if (targetUid != uid || !_syncing.add(targetUid)) return;
    try {
      final changes = await _queue.read(targetUid);
      if (changes.isNotEmpty && taskSyncIssue.value != null) {
        await _queue.acknowledge(targetUid, changes.first['id'] as String);
      }
      taskSyncIssue.value = null;
    } finally {
      _syncing.remove(targetUid);
    }
    unawaited(_flushTaskChanges(targetUid));
  }

  Future<void> saveTask({
    required String targetUid,
    required HabitSchedule definition,
    HabitTask? task,
    String? iconId,
  }) async {
    final now = DateTime.now();
    final today = dayKey(now);
    final next = definition.toDefinition();
    final previous = task?.latest.toDefinition();
    if (definition.kind == 'oneTime' &&
        (definition.oneTimeDate == null ||
            (definition.oneTimeDate != task?.latest.oneTimeDate &&
                definition.oneTimeDate!.compareTo(today) < 0))) {
      throw StateError('Choose today or a future date.');
    }
    if (definition.kind == 'oneTime' &&
        definition.oneTimeDate != task?.latest.oneTimeDate) {
      next['startDate'] = definition.oneTimeDate;
    }
    if (previous != null) {
      next.removeWhere((key, value) {
        return _sameTaskValue(value, previous[key]);
      });
      if (next.isEmpty) return;
    }
    final id =
        task?.id ??
        db.collection('users').doc(targetUid).collection('tasks').doc().id;
    await _enqueue(targetUid, id, task == null ? 'create' : 'edit', {
      'definition': next,
      if (task == null) 'iconId': iconId,
      if (task == null) 'createdAt': now.toUtc().toIso8601String(),
    });
  }

  Future<void> setTaskIcon({
    required String targetUid,
    required String taskId,
    required String? iconId,
  }) => _enqueue(targetUid, taskId, 'icon', {'iconId': iconId});

  Future<void> deleteTask(String targetUid, String taskId) =>
      _enqueue(targetUid, taskId, 'delete', {});

  Future<void> _enqueue(
    String targetUid,
    String taskId,
    String kind,
    Map<String, dynamic> data,
  ) async {
    if (targetUid != uid) throw StateError('Only the task owner can edit it.');
    await _queue.add(targetUid, {
      'id': db.collection('users').doc().id,
      'taskId': taskId,
      'kind': kind,
      'date': dayKey(DateTime.now()),
      'editedAt': DateTime.now().millisecondsSinceEpoch,
      ...data,
    });
    unawaited(_flushTaskChanges(targetUid));
  }

  Future<void> _flushTaskChanges(String targetUid) async {
    if (FirebaseAuth.instance.currentUser?.uid != targetUid ||
        !_syncing.add(targetUid))
      return;
    try {
      while (FirebaseAuth.instance.currentUser?.uid == targetUid) {
        final changes = await _queue.read(targetUid);
        if (changes.isEmpty) return;
        final change = changes.first;
        await _applyTaskChange(targetUid, change);
        await _queue.acknowledge(targetUid, change['id'] as String);
        taskSyncIssue.value = null;
      }
    } on FirebaseException catch (error) {
      if (FirebaseAuth.instance.currentUser?.uid == targetUid &&
          !const {
            'unavailable',
            'deadline-exceeded',
            'aborted',
            'cancelled',
          }.contains(error.code)) {
        taskSyncIssue.value =
            'A task change is waiting to sync (' + error.code + ').';
      }
    } catch (error) {
      if (FirebaseAuth.instance.currentUser?.uid == targetUid) {
        taskSyncIssue.value =
            'A task change is waiting to sync. ' + friendlyError(error);
      }
    } finally {
      _syncing.remove(targetUid);
    }
  }

  Future<void> _applyTaskChange(String targetUid, Map<String, dynamic> change) {
    final user = db.collection('users').doc(targetUid);
    final ref = user.collection('tasks').doc(change['taskId'] as String);
    final kind = change['kind'] as String;
    final syncId = change['id'] as String;
    return db.runTransaction<void>((transaction) async {
      if (FirebaseAuth.instance.currentUser?.uid != targetUid) {
        throw StateError('The account changed before sync.');
      }
      final snapshot = await transaction.get(ref);
      final current = snapshot.data();
      final now = DateTime.now();
      final today = dayKey(now);
      final audit = {
        'updatedBy': targetUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (kind == 'create') {
        if (snapshot.exists) return;
        final definition = change['definition'] as Map<String, dynamic>;
        transaction.set(ref, {
          ...audit,
          'ownerUid': targetUid,
          'createdBy': targetUid,
          'createdAt': FieldValue.serverTimestamp(),
          if (change['iconId'] != null) 'iconId': change['iconId'],
          'versions': [
            {
              ...definition,
              'effectiveFrom': change['date'],
              'syncId': syncId,
              'editedAt': change['editedAt'],
            },
          ],
        });
        return;
      }
      if (current == null || current['deletedOn'] != null) {
        if (kind == 'delete' && current?['deletedOn'] != null) return;
        throw StateError('The task was deleted before this change could sync.');
      }
      if (kind == 'status') {
        final date = change['occurrenceDate'] as String;
        final ref = user
            .collection('occurrences')
            .doc((change['taskId'] as String) + '_' + date);
        final event = user.collection('activity').doc(syncId);
        final previous = await transaction.get(ref);
        final receipt = await transaction.get(event);
        if (receipt.exists) return;
        final status = change['status'] as String;
        final before = previous.data()?['status'] as String? ?? 'pending';
        if (before == status) return;
        transaction.set(ref, {
          'taskId': change['taskId'],
          'date': date,
          'status': status,
          'changedAt': FieldValue.serverTimestamp(),
          'changedBy': targetUid,
        });
        transaction.set(event, {
          'taskId': change['taskId'],
          'date': date,
          'from': before,
          'to': status,
          'by': targetUid,
          'at': FieldValue.serverTimestamp(),
        });
        return;
      }
      if (kind == 'delete') {
        transaction.update(ref, {
          ...audit,
          'deletedOn': today,
          'deletedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      if (kind == 'icon') {
        if (current['iconId'] != change['iconId']) {
          transaction.update(ref, {...audit, 'iconId': change['iconId']});
        }
        return;
      }
      final versions = (current['versions'] as List)
          .cast<Map<String, dynamic>>();
      if (versions.any((version) => version['syncId'] == syncId)) return;
      if (versions.isEmpty || versions.length >= 350) {
        throw StateError('The task has reached its schedule revision limit.');
      }
      final previous = HabitSchedule.fromMap(versions.last);
      final latest = previous.toDefinition();
      final patch = Map<String, dynamic>.from(
        change['definition'] as Map<String, dynamic>,
      );
      final editedAt = change['editedAt'] as int;
      final lastServerWrite =
          (current['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      patch.removeWhere((key, value) {
        if (_sameTaskValue(latest[key], value)) return true;
        // Find the revision that last changed just this field.
        var index = versions.length - 1;
        while (index > 0 &&
            _sameTaskValue(versions[index][key], versions[index - 1][key])) {
          index--;
        }
        final fieldEditedAt =
            versions[index]['editedAt'] as int? ??
            (index == versions.length - 1 ? lastServerWrite : 0);
        return fieldEditedAt > editedAt;
      });
      if (patch.isEmpty) return;
      final next = {
        ...latest,
        ...patch,
        'effectiveFrom': today,
        'syncId': syncId,
        'editedAt': editedAt,
      };
      final schedule = HabitSchedule.fromMap(next);
      if (schedule.kind == 'oneTime' &&
          schedule.oneTimeDate != null &&
          schedule.oneTimeDate != previous.oneTimeDate &&
          schedule.oneTimeDate!.compareTo(today) < 0) {
        throw StateError(
          'The new one-time date passed while offline. Choose a new date.',
        );
      }
      if ((schedule.kind == 'oneTime' && schedule.oneTimeDate == null) ||
          (schedule.kind == 'recurring' && schedule.weekdays.isEmpty) ||
          (schedule.endDate != null &&
              schedule.endDate!.compareTo(schedule.startDate) < 0)) {
        throw StateError(
          'The saved change conflicts with the latest schedule.',
        );
      }
      if (canMoveOneTimeTaskToToday(previous, schedule, now)) {
        final occurrence = await transaction.get(
          user
              .collection('occurrences')
              .doc('${ref.id}_${previous.oneTimeDate}'),
        );
        if (occurrence.exists && occurrence.data()?['status'] != 'pending') {
          throw StateError('Only pending tasks can move to today.');
        }
      }
      transaction.update(ref, {
        ...audit,
        'versions': [...versions, next],
      });
    });
  }

  Future<void> mark({
    required String targetUid,
    required HabitTask task,
    required DateTime date,
    required String status,
    required String previous,
  }) async {
    if (targetUid != uid)
      throw StateError('Admins cannot edit task completion records.');
    if (dayKey(date).compareTo(dayKey(DateTime.now())) > 0) {
      throw StateError('You can record an occurrence on or after its date.');
    }
    if (task.isDeleted || !task.scheduled(date)) {
      throw StateError('This task is not scheduled for that day.');
    }
    if (status == previous) return;
    await _enqueue(targetUid, task.id, 'status', {
      'occurrenceDate': dayKey(date),
      'status': status,
    });
  }

  Future<void> setPreference(
    String targetUid,
    Map<String, dynamic> patch,
  ) async {
    final ref = db
        .collection('users')
        .doc(targetUid)
        .collection('settings')
        .doc('preferences');
    final previous = (await ref.get()).data() ?? <String, dynamic>{};
    await ref.set(<String, dynamic>{
      'darkMode': false,
      'quietHoursEnabled': false,
      'quietStart': 1320,
      'quietEnd': 420,
      'defaultLeadMinutes': 2,
      'defaultRepeatMinutes': 2,
      'notificationsEnabled': true,
      'timezone': 'UTC',
      ...previous,
      ...patch,
    });
  }

  Future<void> snooze(String targetUid, String taskId, int minutes) async {
    if (targetUid != uid) throw StateError('Only the task owner can snooze.');
    await db
        .collection('users')
        .doc(uid)
        .collection('reminderStates')
        .doc(taskId)
        .set({
          'snoozeUntil': Timestamp.fromDate(
            DateTime.now().add(Duration(minutes: minutes)),
          ),
        }, SetOptions(merge: true));
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final email = currentUser.email;
    if (email == null) throw StateError('Account has no login identifier.');
    await currentUser.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: currentPassword),
    );
    await currentUser.updatePassword(newPassword);
  }
}

bool _sameTaskValue(Object? a, Object? b) =>
    a is List && b is List ? listEquals(a, b) : a == b;

String friendlyError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect ID or password.';
      case 'user-disabled':
        return 'This account is disabled. Contact your administrator.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      default:
        return error.message ?? error.code;
    }
  }
  return error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}
