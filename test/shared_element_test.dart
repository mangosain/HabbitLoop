import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/widgets/brand.dart';
import 'package:habitloop/widgets/shared_element.dart';
import 'package:material_ui/material_ui.dart';

Widget flightHarness({bool reduceMotion = false}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Align(
        alignment: Alignment.bottomRight,
        child: SharedIcon(
          tag: 'task',
          icon: Icons.add_rounded,
          child: IconButton(
            tooltip: 'Add task',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Navigator.of(context).push(
              sharedRoute<void>(
                context,
                const Scaffold(
                  body: Center(
                    child: SharedIcon(
                      tag: 'task',
                      icon: Icons.wb_sunny_outlined,
                      child: Icon(Icons.wb_sunny_outlined, size: 80),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the branded splash shows its logo and a loading status', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandLoading())),
    );
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.text('HabitLoop'), findsOneWidget);
    expect(find.text('Small steps, big changes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the splash logo moves and shrinks into the next header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Stack(
              children: [
                const BrandLoading(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      sharedRoute<void>(
                        context,
                        const Scaffold(
                          body: Align(
                            alignment: Alignment.topLeft,
                            child: BrandHeader(),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final tile = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == 'assets/art/brand_tile.png',
    );
    final start = tester.getCenter(tile);
    final startWidth = tester.getSize(tile).width;
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tile, findsOneWidget);
    final inFlight = tester.getCenter(tile);
    final inFlightWidth = tester.getSize(tile).width;
    await tester.pumpAndSettle();
    final end = tester.getCenter(tile);
    final endWidth = tester.getSize(tile).width;

    expect(inFlight.dx, inExclusiveRange(end.dx, start.dx));
    expect(inFlight.dy, inExclusiveRange(end.dy, start.dy));
    expect(inFlightWidth, inExclusiveRange(endWidth, startWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the task icon travels and morphs in both directions', (
    tester,
  ) async {
    await tester.pumpWidget(flightHarness());
    final add = find.byIcon(Icons.add_rounded);
    final sun = find.byIcon(Icons.wb_sunny_outlined);
    final start = tester.getCenter(add);
    await tester.tap(find.byTooltip('Add task'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(add, findsOneWidget);
    expect(sun, findsOneWidget);
    expect(tester.getCenter(add), isNot(start));
    expect(tester.getCenter(add), tester.getCenter(sun));
    await tester.pumpAndSettle();
    expect(sun, findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(add, findsOneWidget);
    expect(sun, findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.getCenter(add), start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion skips the shared-element flight', (tester) async {
    await tester.pumpWidget(flightHarness(reduceMotion: true));
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
