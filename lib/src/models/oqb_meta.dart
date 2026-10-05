import 'oqb_json.dart';

/// Human-readable labels from `/public/meta.json`.
///
/// The file is known to contain subjects, topics, subtopics, difficulties,
/// publishers and school levels, but its exact layout has not been captured.
/// This parser therefore only builds a code → label index from any list/map
/// entry that carries a code-like and a name-like field, and every lookup
/// falls back to the raw code. Nothing in the app depends on a label existing.
class OqbMeta {
  const OqbMeta({this.labels = const <String, OqbLabel>{}});

  static const empty = OqbMeta();

  final Map<String, OqbLabel> labels;

  bool get isEmpty => labels.isEmpty;

  /// Label for any code (subject, topic, publisher...). Falls back to [code].
  String label(String code, {bool preferEnglish = false}) {
    final entry = labels[code] ?? labels[code.toLowerCase()];
    if (entry == null) return code;
    return entry.pick(preferEnglish: preferEnglish) ?? code;
  }

  /// Difficulty codes are small integers; meta may index them under any key.
  String difficulty(int code) {
    for (final key in ['difficulty_$code', 'difficulty:$code']) {
      final entry = labels[key];
      if (entry != null) return entry.pick() ?? 'Level $code';
    }
    return 'Level $code';
  }

  factory OqbMeta.fromJson(dynamic json) {
    final labels = <String, OqbLabel>{};

    void visit(dynamic node, String section, int depth) {
      if (depth > 6) return;
      if (node is Map) {
        final map = asMap(node);
        final code = _codeOf(map);
        final label = OqbLabel.fromMap(map);
        if (code != null && label != null) {
          labels.putIfAbsent(code, () => label);
          if (section.contains('difficult')) {
            labels.putIfAbsent('difficulty_$code', () => label);
          }
        }
        for (final entry in map.entries) {
          final value = entry.value;
          if (value is String && depth > 0 && _looksLikeCode(entry.key)) {
            // e.g. {"econ": "Economics"} style dictionaries.
            labels.putIfAbsent(entry.key, () => OqbLabel(zh: value, en: ''));
          } else if (value is Map || value is List) {
            if (value is Map && depth > 0 && _looksLikeCode(entry.key)) {
              // e.g. {"econ_5": {"name_en": "..."}} keyed by code.
              final nested = asMap(value);
              final label = OqbLabel.fromMap(nested);
              if (_codeOf(nested) == null && label != null) {
                labels.putIfAbsent(entry.key, () => label);
              }
            }
            visit(value, depth == 0 ? entry.key.toLowerCase() : section, depth + 1);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item, section, depth + 1);
        }
      }
    }

    visit(json, '', 0);
    return OqbMeta(labels: labels);
  }

  static String? _codeOf(Map<String, dynamic> map) {
    for (final key in const ['code', 'topic_code', 'subtopic_code', 'subject_code', 'publisher_code', 'difficulty_code']) {
      final value = asString(map[key]);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static bool _looksLikeCode(String key) =>
      RegExp(r'^[A-Za-z0-9_\-]{1,40}$').hasMatch(key);
}

class OqbLabel {
  const OqbLabel({required this.zh, required this.en});

  final String zh;
  final String en;

  String? pick({bool preferEnglish = false}) {
    final first = preferEnglish ? en : zh;
    final second = preferEnglish ? zh : en;
    if (first.isNotEmpty) return first;
    if (second.isNotEmpty) return second;
    return null;
  }

  static OqbLabel? fromMap(Map<String, dynamic> map) {
    String first(List<String> keys) {
      for (final key in keys) {
        final value = asString(map[key]);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final zh = first(const ['title_zh', 'name_zh', 'label_zh', 'zh', 'title_tc', 'name_tc']);
    final en = first(const ['title_en', 'name_en', 'label_en', 'en']);
    final generic = first(const ['title', 'name', 'label', 'description']);
    if (zh.isEmpty && en.isEmpty && generic.isEmpty) return null;
    return OqbLabel(zh: zh.isNotEmpty ? zh : generic, en: en);
  }
}
