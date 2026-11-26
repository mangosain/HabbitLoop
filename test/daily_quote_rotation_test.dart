import 'package:flutter_test/flutter_test.dart';
import 'package:habitloop/services/daily_quote_rotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<RemoteQuote> batch(String prefix) => [
  for (var i = 0; i < 10; i++) RemoteQuote('$prefix $i', 'Author'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'one batch rotates on opens and keeps its place across restarts',
    () async {
      var requests = 0;
      var date = DateTime(2026, 11, 25);
      Future<List<RemoteQuote>> fetch() async => batch('Batch ${++requests}');
      final first = DailyQuoteRotation(fetch: fetch, now: () => date);

      await first.open();
      expect(first.current.value?.text, 'Batch 1 0');
      await first.retryWhenConnected();
      expect(first.current.value?.text, 'Batch 1 0');
      await first.open();
      expect(first.current.value?.text, 'Batch 1 1');

      final restarted = DailyQuoteRotation(fetch: fetch, now: () => date);
      for (var i = 2; i < 10; i++) {
        await restarted.open();
        expect(restarted.current.value?.text, 'Batch 1 $i');
      }
      await restarted.open();
      expect(restarted.current.value?.text, 'Batch 1 0');
      expect(requests, 1);

      date = DateTime(2026, 11, 26);
      await restarted.open();
      expect(restarted.current.value?.text, 'Batch 2 0');
      expect(requests, 2);
    },
  );

  test(
    'a new day excludes the last cached batch and duplicates in a response',
    () async {
      var date = DateTime(2026, 11, 25);
      var requests = 0;
      final yesterday = batch('Yesterday');
      final fresh = batch('Fresh');
      final first = DailyQuoteRotation(
        fetch: () async => yesterday,
        now: () => date,
      );
      await first.open();

      date = DateTime(2026, 11, 26);
      final nextDay = DailyQuoteRotation(
        fetch: () async {
          requests++;
          return [
            const RemoteQuote('  yESTERDAY   0 ', 'Different author'),
            ...yesterday,
            fresh.first,
            fresh.first,
            ...fresh.skip(1),
          ];
        },
        now: () => date,
      );
      for (final quote in fresh) {
        await nextDay.open();
        expect(nextDay.current.value?.text, quote.text);
      }
      expect(requests, 1);
    },
  );

  test(
    'a repeated provider page is filled with distinct bundled quotes',
    () async {
      var date = DateTime(2026, 11, 25);
      final source = batch('Old');
      final rotation = DailyQuoteRotation(
        fetch: () async => source,
        now: () => date,
      );
      await rotation.open();
      date = DateTime(2026, 11, 26);
      final shown = <String>{};
      for (var i = 0; i < 10; i++) {
        await rotation.open();
        final quote = rotation.current.value!;
        expect(quote.author, isNull);
        expect(source.any((old) => old.text == quote.text), isFalse);
        shown.add(quote.text);
      }
      expect(shown, hasLength(10));
    },
  );

  test(
    'offline fallback clears once a batch arrives after reconnecting',
    () async {
      var online = false;
      var requests = 0;
      final rotation = DailyQuoteRotation(
        now: () => DateTime(2026, 11, 25),
        fetch: () async {
          requests++;
          if (!online) throw StateError('Offline');
          return batch('Online');
        },
      );

      await rotation.open();
      expect(rotation.current.value, isNull);
      online = true;
      await rotation.retryWhenConnected();
      expect(rotation.current.value?.text, 'Online 0');
      await rotation.retryWhenConnected();
      expect(rotation.current.value?.text, 'Online 0');
      await rotation.open();
      expect(rotation.current.value?.text, 'Online 1');
      expect(requests, 2);
    },
  );
}
