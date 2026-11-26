import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/widgets/calendar_board.dart';
import 'package:material_ui/material_ui.dart';

Widget calendar({required bool reduceMotion}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: CalendarBoard(
        uid: 'test-user',
        tasks: const [],
        entries: const [],
        initialMonth: DateTime(2026, 1),
      ),
    ),
  ),
);

void main() {
  final january = find.byKey(ValueKey(DateTime(2026, 1)));
  final february = find.byKey(ValueKey(DateTime(2026, 2)));

  testWidgets('month navigation animates between populated grids', (
    tester,
  ) async {
    await tester.pumpWidget(calendar(reduceMotion: false));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    expect(january, findsOneWidget);
    expect(february, findsOneWidget);
    await tester.pumpAndSettle();
    expect(january, findsNothing);
    expect(find.text('February 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month navigation changes immediately with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(calendar(reduceMotion: true));
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pump();
    expect(january, findsNothing);
    expect(february, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
