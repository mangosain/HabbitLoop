import 'package:material_ui/material_ui.dart';

import 'common.dart';
import 'material_task_icons.dart';

const _suggestedIcons = {
  'fitness': ('Exercise', Icons.fitness_center_rounded),
  'walk': ('Walk or run', Icons.directions_run_rounded),
  'water': ('Water', Icons.water_drop_rounded),
  'medicine': ('Medication', Icons.medication_rounded),
  'food': ('Food', Icons.restaurant_rounded),
  'study': ('Study or read', Icons.menu_book_rounded),
  'work': ('Work', Icons.laptop_mac_rounded),
  'mindfulness': ('Mindfulness', Icons.spa_rounded),
  'sleep': ('Sleep', Icons.bedtime_rounded),
  'hygiene': ('Personal care', Icons.bathtub_rounded),
  'home': ('Home', Icons.cleaning_services_rounded),
  'money': ('Money', Icons.savings_rounded),
  'pet': ('Pets', Icons.pets_rounded),
  'music': ('Music', Icons.music_note_rounded),
  'sun': ('Personal', Icons.wb_sunny_outlined),
};

final _titlePatterns = {
  'medicine': RegExp(
    r'\b(medicine|medication|meds|pill|pills|vitamin|vitamins|supplements?|dawai|dawa)\b',
  ),
  'pet': RegExp(r'\b(dog|cat|pet|puppy|kitten)\b'),
  'water': RegExp(r'\b(water|hydrate|hydration)\b'),
  'mindfulness': RegExp(
    r'\b(meditat\w*|mindful\w*|breathing|journal\w*|yoga)\b',
  ),
  'sleep': RegExp(r'\b(sleep|bedtime|nap|go to bed|wake up)\b'),
  'hygiene': RegExp(r'\b(teeth|floss|shower|skincare|bath)\b'),
  'walk': RegExp(r'\b(walk\w*|run|running|jog\w*|hike|steps?)\b'),
  'fitness': RegExp(
    r'\b(exercise|workout|gym|lifting|pushups?|fitness|stretch\w*|cycling|swim\w*)\b',
  ),
  'tv': RegExp(r'\b(tv|television|telly|watch a show)\b'),
  'movie': RegExp(r'\b(movies?|films?|cinema)\b'),
  'food': RegExp(r'\b(cook\w*|meal\w*|breakfast|lunch|dinner|grocer\w*|eat)\b'),
  'study': RegExp(r'\b(study\w*|read\w*|book\w*|homework|revis\w*|learn\w*)\b'),
  'money': RegExp(r'\b(budget\w*|bills?|financ\w*|expenses?|savings)\b'),
  'home': RegExp(r'\b(clean\w*|laundry|dishes|vacuum\w*|tidy\w*)\b'),
  'music': RegExp(r'\b(music|piano|guitar|sing\w*)\b'),
  'work': RegExp(r'\b(work|meetings?|projects?|email\w*|code|coding)\b'),
};

const _materialPrefix = 'material_';
final _words = RegExp(r'[a-z0-9]+');

class TaskIconOption {
  TaskIconOption(this.id, this.label, this.icon, {String aliases = ''})
    : _searchText = '$label $aliases'.toLowerCase();

  final String id;
  final String label;
  final IconData icon;
  final String _searchText;
}

const _iconAliases = {
  'directions_bike': 'bicycle cycling',
  'directions_car': 'auto vehicle',
  'flight': 'airplane travel',
  'favorite': 'heart love',
  'vaccines': 'shot injection',
  'local_hospital': 'medical first aid',
  'school': 'education graduate',
  'restaurant': 'food meal eat',
  'sports_esports': 'game gaming videogame console controller',
  'water_drop': 'drink hydration',
};

final _taskIconOptions = List<TaskIconOption>.unmodifiable([
  for (final entry in _suggestedIcons.entries)
    TaskIconOption(entry.key, entry.value.$1, entry.value.$2),
  for (final entry in materialTaskIcons.entries)
    if (!_suggestedGlyphs.contains(entry.value))
      TaskIconOption(
        '$_materialPrefix${entry.key}',
        entry.key.replaceAll('_', ' '),
        entry.value,
        aliases: _iconAliases[entry.key] ?? '',
      ),
]);

final _suggestedGlyphs = {
  for (final option in _suggestedIcons.values) option.$2,
};

List<TaskIconOption> searchTaskIcons(String query) {
  final tokens = _words
      .allMatches(query.toLowerCase())
      .map((m) => m[0]!)
      .toList();
  if (tokens.isEmpty) return _taskIconOptions;
  return _taskIconOptions
      .where((option) => tokens.every(option._searchText.contains))
      .toList(growable: false);
}

const _titleStopWords = {
  'a',
  'an',
  'and',
  'at',
  'check',
  'daily',
  'do',
  'every',
  'for',
  'go',
  'in',
  'maintenance',
  'my',
  'of',
  'on',
  'play',
  'session',
  'task',
  'the',
  'to',
  'today',
  'watch',
  'with',
};

final _titleIconIndex = _indexTitleIcons();

Map<String, List<TaskIconOption>> _indexTitleIcons() {
  final index = <String, List<TaskIconOption>>{};
  for (final option in _taskIconOptions) {
    final words = _words
        .allMatches(option._searchText)
        .map((match) => match[0]!)
        .toSet();
    for (final word in words) {
      (index[word] ??= []).add(option);
    }
  }
  return index;
}

IconData? _catalogIcon(String title) {
  final words = _words.allMatches(title).map((match) => match[0]!).toSet();
  final scores = <TaskIconOption, int>{};
  for (final word in words) {
    if (word.length < 2 || _titleStopWords.contains(word)) continue;
    final options = _titleIconIndex[word];
    if (options == null) continue;
    final weight = 100 + (80 ~/ options.length);
    for (final option in options) {
      scores.update(option, (score) => score + weight, ifAbsent: () => weight);
    }
  }
  TaskIconOption? best;
  var bestScore = 0;
  for (final entry in scores.entries) {
    final score = entry.value;
    if (score > bestScore ||
        (score == bestScore && entry.key.label.length < best!.label.length)) {
      best = entry.key;
      bestScore = score;
    }
  }
  return best?.icon;
}

IconData taskIcon(String title, String category, {String? iconId}) {
  final custom = _suggestedIcons[iconId];
  if (custom != null) return custom.$2;
  if (iconId != null && iconId.startsWith(_materialPrefix)) {
    final icon = materialTaskIcons[iconId.substring(_materialPrefix.length)];
    if (icon != null) return icon;
  }
  final normalized = title.toLowerCase();
  for (final pattern in _titlePatterns.entries) {
    if (pattern.value.hasMatch(normalized)) {
      return _suggestedIcons[pattern.key]?.$2 ??
          materialTaskIcons[pattern.key]!;
    }
  }
  return _catalogIcon(normalized) ?? taskCategoryIcon(category);
}
