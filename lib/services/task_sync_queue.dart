import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TaskSyncQueue {
  final _preferences = SharedPreferencesAsync();
  final _changes = StreamController<String>.broadcast();
  Future<void> _tail = Future.value();

  Stream<String> get changes => _changes.stream;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  String _key(String uid) => 'task-sync-v1:$uid';

  Future<List<Map<String, dynamic>>> _read(String uid) async {
    final value = await _preferences.getString(_key(uid));
    return value == null
        ? []
        : (jsonDecode(value) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> read(String uid) =>
      _serialized(() => _read(uid));

  Future<void> add(String uid, Map<String, dynamic> change) =>
      _serialized(() async {
        final pending = await _read(uid);
        pending.add(change);
        await _preferences.setString(_key(uid), jsonEncode(pending));
        _changes.add(uid);
      });

  Future<void> acknowledge(String uid, String id) => _serialized(() async {
    final pending = await _read(uid);
    pending.removeWhere((item) => item['id'] == id);
    await _preferences.setString(_key(uid), jsonEncode(pending));
    _changes.add(uid);
  });
}
