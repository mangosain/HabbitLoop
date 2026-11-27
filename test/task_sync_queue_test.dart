import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/services/task_sync_queue.dart';
// The plugin's in-memory platform implementation preserves native semantics.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('queued edits reload in order and are isolated by account', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final queue = TaskSyncQueue();
    const first = {'id': 'first', 'kind': 'create'};
    const second = {'id': 'second', 'kind': 'edit'};
    await Future.wait([queue.add('a', first), queue.add('a', second)]);
    final reopened = TaskSyncQueue();
    expect(await reopened.read('a'), [first, second]);
    expect(await reopened.read('b'), isEmpty);
    await reopened.acknowledge('a', 'first');
    expect(await TaskSyncQueue().read('a'), [second]);
  });
}
