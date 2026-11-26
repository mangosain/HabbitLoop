import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/widgets/firebase_connection_banner.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('brief cache use stays hidden and reconnect clears the banner', (
    tester,
  ) async {
    final monitor = FirebaseAvailabilityMonitor();
    addTearDown(monitor.dispose);
    const screen = Key('screen');
    const label = 'Firebase connection unavailable';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            FirebaseConnectionBanner(monitor: monitor, child: child!),
        home: const Scaffold(body: Text('Dashboard', key: screen)),
      ),
    );
    final initialScreen = tester.element(find.byKey(screen));

    monitor.observeSnapshot(fromCache: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(label), findsNothing);
    monitor.observeSnapshot(fromCache: false);
    await tester.pump(FirebaseAvailabilityMonitor.cacheGrace);
    expect(find.text(label), findsNothing);

    monitor.observeSnapshot(fromCache: true);
    await tester.pump(FirebaseAvailabilityMonitor.cacheGrace);
    expect(find.text(label), findsOneWidget);
    expect(tester.element(find.byKey(screen)), same(initialScreen));

    monitor.observeSnapshot(fromCache: false);
    await tester.pump();
    expect(find.text(label), findsNothing);
  });

  test(
    'authentication network errors are distinguished from invalid login',
    () {
      final monitor = FirebaseAvailabilityMonitor();
      addTearDown(monitor.dispose);
      monitor.observeAuthError(
        FirebaseException(plugin: 'firebase_auth', code: 'invalid-credential'),
      );
      expect(monitor.value, FirebaseAvailability.unknown);
      monitor.observeAuthError(
        FirebaseException(
          plugin: 'firebase_auth',
          code: 'network-request-failed',
        ),
      );
      expect(monitor.value, FirebaseAvailability.unavailable);
      monitor.reset();
      expect(monitor.value, FirebaseAvailability.unknown);
    },
  );
}
