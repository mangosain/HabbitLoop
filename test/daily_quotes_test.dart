import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/models/daily_quotes.dart';
import 'package:habitloop/widgets/daily_quote_card.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('quotes rotate without repeats across months and stay short', () {
    final first = DateTime(2026, 1, 30);
    final cycle = [
      for (var i = 0; i < dailyQuotes.length; i++)
        quoteForDay(DateTime(first.year, first.month, first.day + i)),
    ];
    expect(dailyQuotes, hasLength(84));
    expect(cycle.toSet(), hasLength(dailyQuotes.length));
    expect(dailyQuotes.every((quote) => quote.length <= 55), isTrue);
    expect(quoteForDay(DateTime(2026, 1, 30, 23, 59)), cycle.first);
    expect(
      quoteForDay(DateTime(2026, 1, 30 + dailyQuotes.length)),
      cycle.first,
    );
  });

  testWidgets('narrow cards limit lines and open the full quote', (
    tester,
  ) async {
    const quote = 'Make one useful decision before the day gets busy.';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 110, child: DailyQuoteCard(quote)),
          ),
        ),
      ),
    );
    final preview = tester.widget<Text>(find.text(quote));
    expect(preview.maxLines, 5);
    expect(preview.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(quote));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final fullText = tester.widget<Text>(
      find.descendant(of: dialog, matching: find.text(quote)),
    );
    expect(fullText.maxLines, isNull);
    expect(tester.takeException(), isNull);
  });
}
