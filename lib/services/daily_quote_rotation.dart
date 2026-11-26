import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/habit.dart' show dayKey;
import '../models/daily_quotes.dart';

const _batchSize = 10;
const _candidateCount = 30;
const _cacheKey = 'daily_quote_rotation_v1';

class RemoteQuote {
  const RemoteQuote(this.text, this.author);

  final String text;
  final String? author;

  static RemoteQuote? fromJson(Object? value) {
    if (value is! Map || value['quote'] is! String) return null;
    final text = (value['quote'] as String).trim();
    if (text.isEmpty || text.length > 500) return null;
    final rawAuthor = value['author'];
    final author = rawAuthor is String ? rawAuthor.trim() : null;
    return RemoteQuote(text, author == null || author.isEmpty ? null : author);
  }

  Map<String, Object?> toJson() => {'quote': text, 'author': author};
}

class DailyQuoteRotation {
  DailyQuoteRotation({
    Future<List<RemoteQuote>> Function()? fetch,
    DateTime Function()? now,
  }) : _fetch = fetch,
       _now = now ?? DateTime.now;

  static final instance = DailyQuoteRotation();

  final Future<List<RemoteQuote>> Function()? _fetch;
  final DateTime Function() _now;
  final current = ValueNotifier<RemoteQuote?>(null);
  Future<void> _work = Future<void>.value();
  String? _day;
  List<RemoteQuote> _batch = const [];
  int _next = 0;
  int _knownTotal = 0;
  Set<String> _previousTexts = {};
  final _random = Random();
  static final _space = RegExp(r"\s+");

  Future<void> open() => _enqueue(advance: true);

  Future<void> retryWhenConnected() => _enqueue(advance: false);

  Future<void> _enqueue({required bool advance}) {
    _work = _work.then((_) => _refresh(advance: advance));
    return _work;
  }

  Future<void> _refresh({required bool advance}) async {
    try {
      final today = dayKey(_now());
      final prefs = await SharedPreferences.getInstance();
      if (_day != today) {
        _day = today;
        _batch = const [];
        _next = 0;
        _previousTexts = {};
        current.value = null;
        _restore(prefs, today);
      }
      if (_batch.isNotEmpty) {
        if (!advance) return;
      } else {
        final candidates = await (_fetch?.call() ?? _fetchCandidates());
        if (candidates.isEmpty || dayKey(_now()) != today) return;
        _batch = _selectBatch(candidates);
      }
      current.value = _batch[_next];
      _next = (_next + 1) % _batch.length;
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'day': today,
          'next': _next,
          'quotes': _batch,
          'total': _knownTotal,
        }),
      );
    } catch (_) {
      // An unavailable provider or cache must not interrupt the dashboard.
    }
  }

  void _restore(SharedPreferences prefs, String today) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final cache = jsonDecode(raw);
      if (cache is! Map) return;
      final total = cache['total'];
      if (total is int && total > 0) _knownTotal = total;
      final batch = _decodeBatch(cache['quotes']);
      if (batch.length != _batchSize) return;
      if (cache['day'] != today) {
        _previousTexts = {for (final quote in batch) _key(quote.text)};
        return;
      }
      _batch = batch;
      final next = cache['next'];
      if (next is int && next >= 0 && next < _batchSize) _next = next;
    } on FormatException {
      // Treat a corrupt cache as a new day with no fetched batch yet.
    }
  }

  static List<RemoteQuote> _decodeBatch(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (RemoteQuote.fromJson(item) case final quote?) quote,
    ];
  }

  static String _key(String text) =>
      text.trim().toLowerCase().replaceAll(_space, ' ');

  List<RemoteQuote> _selectBatch(List<RemoteQuote> candidates) {
    final excluded = {..._previousTexts};
    final selected = <RemoteQuote>[];
    for (final quote in candidates) {
      if (excluded.add(_key(quote.text))) selected.add(quote);
      if (selected.length == _batchSize) return selected;
    }
    final fallback = [...dailyQuotes]..shuffle(_random);
    for (final text in fallback) {
      if (excluded.add(_key(text))) selected.add(RemoteQuote(text, null));
      if (selected.length == _batchSize) break;
    }
    return selected;
  }

  Future<List<RemoteQuote>> _fetchCandidates() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final maxSkip = max(0, _knownTotal - _candidateCount);
    final skip = _random.nextInt(maxSkip + 1);
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.https('dummyjson.com', '/quotes', {
            'limit': '$_candidateCount',
            'skip': '$skip',
            'select': 'quote,author',
          }),
        );
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) return <RemoteQuote>[];
        final body = await utf8.decoder.bind(response).join();
        final page = jsonDecode(body);
        if (page is! Map) return <RemoteQuote>[];
        final total = page['total'];
        if (total is int && total > 0) _knownTotal = total;
        return [..._decodeBatch(page['quotes'])]..shuffle(_random);
      })().timeout(const Duration(seconds: 6));
    } finally {
      client.close(force: true);
    }
  }
}
