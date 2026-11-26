import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/habit.dart';

class HabitBackend {
  static final HabitBackend instance = HabitBackend._();
  HabitBackend._();
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String get uid => FirebaseAuth.instance.currentUser!.uid;
  String userEmail(String username) =>
      '${username.toLowerCase().trim()}@habitloop.example';

  Stream<DocumentSnapshot<Map<String, dynamic>>> profile(String targetUid) => db
      .collection('users')
      .doc(targetUid)
      .snapshots(includeMetadataChanges: true);
  Stream<List<HabitTask>> tasks(String targetUid) => _watchCollection(
    db.collection('users').doc(targetUid).collection('tasks'),
    HabitTask.fromDoc,
  ).map((tasks) => tasks.where((task) => task.versions.isNotEmpty).toList());

  Stream<List<HabitEntry>> entries(String targetUid, {String? date}) {
    final collection = db
        .collection('users')
        .doc(targetUid)
        .collection('occurrences');
    final query = date == null
        ? collection
        : collection.where('date', isEqualTo: date);
    return _watchCollection(query, HabitEntry.fromDoc);
  }

  Stream<List<T>> _watchCollection<T>(
    Query<Map<String, dynamic>> query,
    T Function(DocumentSnapshot<Map<String, dynamic>>) parse,
  ) async* {
    final byId = <String, T>{};
    await for (final snapshot in query.snapshots()) {
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

  Future<void> logout() => FirebaseAuth.instance.signOut();

  /// Spark-compatible: client transaction + server-enforced append-only history.
  /// Edits normally apply tomorrow. A missed one-time task can move to today. Admins cannot
  /// change completion history. Firestore rules are the security boundary.
  Future<void> saveTask({
    required String targetUid,
    required HabitSchedule definition,
    String? taskId,
    String? iconId,
  }) async {
    final now = DateTime.now();
    final today = dayKey(now);
    final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
    // Firestore also enforces a UTC lower bound. Match it on the client.
    final utc = now.toUtc();
    final utcToday = dayKey(utc);
    final utcTomorrow = dayKey(DateTime.utc(utc.year, utc.month, utc.day + 1));
    final localEffective = taskId == null ? today : tomorrow;
    final utcEffective = taskId == null ? utcToday : utcTomorrow;
    final effective = localEffective.compareTo(utcEffective) >= 0
        ? localEffective
        : utcEffective;
    final raw = definition.toDefinition();
    final selectedDate = definition.oneTimeDate;
    final moveToToday =
        taskId != null && definition.kind == 'oneTime' && selectedDate == today;
    if (definition.kind == 'oneTime' &&
        (selectedDate == null ||
            (!moveToToday && selectedDate.compareTo(effective) < 0))) {
      throw StateError('Choose a one-time date on or after $effective.');
    }
    if ((taskId == null &&
            (raw['startDate'] as String).compareTo(effective) < 0) ||
        moveToToday) {
      raw['startDate'] = moveToToday ? today : effective;
    }
    final version = <String, dynamic>{
      ...raw,
      'effectiveFrom': moveToToday ? today : effective,
    };
    final col = db.collection('users').doc(targetUid).collection('tasks');
    final ref = taskId == null ? col.doc() : col.doc(taskId);
    await db.runTransaction<void>((transaction) async {
      if (taskId == null) {
        transaction.set(ref, {
          'versions': [version],
          if (iconId != null) 'iconId': iconId,
          'ownerUid': targetUid,
          'createdBy': uid,
          'updatedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final snap = await transaction.get(ref);
        if (!snap.exists) throw StateError('Task not found.');
        final existing = List<dynamic>.from(
          snap.data()?['versions'] as List? ?? [],
        );
        if (existing.isEmpty || existing.length >= 350) {
          throw StateError(
            'Task has no schedule or has reached its version limit.',
          );
        }
        if (moveToToday) {
          final previous = HabitSchedule.fromMap(
            Map<String, dynamic>.from(existing.last as Map),
          );
          if (!canMoveOneTimeTaskToToday(previous, definition, now)) {
            throw StateError(
              'Only a missed one-time task can move to today. '
              'For other schedule changes, choose $effective or later.',
            );
          }
          final occurrence = await transaction.get(
            ref.parent.parent!
                .collection('occurrences')
                .doc('${taskId}_${previous.oneTimeDate}'),
          );
          if (occurrence.exists && occurrence.data()?['status'] != 'pending') {
            throw StateError('Only pending tasks can move to today.');
          }
        }
        transaction.update(ref, {
          'versions': [...existing, version],
          'updatedBy': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> setTaskIcon({
    required String targetUid,
    required String taskId,
    required String? iconId,
  }) => db
      .collection('users')
      .doc(targetUid)
      .collection('tasks')
      .doc(taskId)
      .update({
        'iconId': iconId,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> mark({
    required String targetUid,
    required HabitTask task,
    required DateTime date,
    required String status,
    required String previous,
  }) async {
    if (targetUid != uid)
      throw StateError('Admins cannot edit task completion records.');
    if (!task.scheduled(date))
      throw StateError('This task is not scheduled for that day.');
    final key = dayKey(date);
    final userDoc = db.collection('users').doc(uid);
    final batch = db.batch();
    batch.set(userDoc.collection('occurrences').doc('${task.id}_$key'), {
      'taskId': task.id,
      'date': key,
      'status': status,
      'changedAt': FieldValue.serverTimestamp(),
      'changedBy': uid,
    });
    batch.set(userDoc.collection('activity').doc(), {
      'taskId': task.id,
      'date': key,
      'from': previous,
      'to': status,
      'by': uid,
      'at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
