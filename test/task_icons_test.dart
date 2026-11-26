import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/widgets/task_icons.dart';
import 'package:habitloop/widgets/task_icon_picker.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('titles choose a relevant icon before using the category fallback', () {
    expect(taskIcon('Eat. Dawai', 'Personal'), Icons.medication_rounded);
    expect(taskIcon('Drink water', 'Health'), Icons.water_drop_rounded);
    expect(
      taskIcon('Morning exercise', 'Personal'),
      Icons.fitness_center_rounded,
    );
    expect(taskIcon('Daily check-in', 'Work'), Icons.laptop_mac_rounded);
  });

  test('TV and movie titles use icons from the expanded catalog', () {
    expect(taskIcon('TV', 'Personal'), Icons.tv_rounded);
    expect(taskIcon('Watch television', 'Personal'), Icons.tv_rounded);
    expect(taskIcon('Movie night', 'Personal'), Icons.movie_rounded);
    expect(taskIcon('ATV maintenance', 'Personal'), Icons.wb_sunny_outlined);
  });

  test(
    'automatic suggestions look up meaningful words in the whole catalog',
    () {
      expect(taskIcon('Game', 'Personal'), Icons.sports_esports_rounded);
      expect(
        taskIcon('Play basketball', 'Personal'),
        Icons.sports_basketball_rounded,
      );
      expect(taskIcon('Pack my umbrella', 'Personal'), Icons.umbrella_rounded);
      expect(
        taskIcon('My daily check', 'Health'),
        Icons.fitness_center_rounded,
      );
      expect(
        searchTaskIcons('game')
            .any((option) => option.icon == Icons.sports_esports_rounded),
        isTrue,
      );
    },
  );

  test('a recognized manual choice overrides the title', () {
    expect(
      taskIcon('Drink water', 'Health', iconId: 'sun'),
      Icons.wb_sunny_outlined,
    );
    expect(
      taskIcon('Drink water', 'Health', iconId: 'unknown'),
      Icons.water_drop_rounded,
    );
  });

  test('the catalog finds expanded icon names and keeps their IDs stable', () {
    expect(searchTaskIcons('').length, greaterThan(2100));
    final bike = searchTaskIcons('BICYCLE')
        .firstWhere((item) => item.id == 'material_directions_bike');
    expect(bike.icon, Icons.directions_bike_rounded);
    expect(taskIcon('Drink water', 'Health', iconId: bike.id), bike.icon);
    expect(searchTaskIcons('not a real icon xyz'), isEmpty);
  });

  testWidgets(
    'the picker builds visible tiles and returns a search selection',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showDialog<String>(
                    context: context,
                    builder: (_) => const TaskIconPicker(selectedId: null),
                  );
                },
                child: const Text('Choose icon'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose icon'));
      await tester.pumpAndSettle();
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.byType(TextButton).evaluate().length, lessThan(80));

      await tester.enterText(find.byType(TextField), 'xyz nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('No matching icons'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bicycle');
      await tester.pumpAndSettle();
      await tester.tap(find.text('directions bike'));
      await tester.pumpAndSettle();
      expect(selected, 'material_directions_bike');
    },
  );
}
