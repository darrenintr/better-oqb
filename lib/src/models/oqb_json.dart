import 'dart:convert';

/// Defensive readers for the observed (undocumented) OQB JSON API.
///
/// OQB is free to change field types (numbers as strings, booleans as 0/1,
/// JSON encoded inside strings). Every model parses through these helpers so
/// that a surprising value degrades to a default instead of throwing.

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  if (value is String && value.trim().startsWith('{')) {
    try {
      return asMap(jsonDecode(value));
    } catch (_) {}
  }
  return const <String, dynamic>{};
}

List<dynamic> asList(dynamic value) {
  if (value is List) return value;
  if (value is Map) return value.values.toList(growable: false);
  return const <dynamic>[];
}

List<Map<String, dynamic>> asMapList(dynamic value) =>
    asList(value).whereType<Map>().map(asMap).toList(growable: false);

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  return int.tryParse('${value ?? ''}'.trim()) ?? fallback;
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value'.trim());
}

num? asNum(dynamic value) {
  if (value is num) return value;
  if (value == null) return null;
  return num.tryParse('$value'.trim());
}

bool? asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0' || text == '') return false;
  return null;
}

String asString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return '';
}

List<String> asStringList(dynamic value) {
  if (value is String && value.trim().startsWith('[')) {
    try {
      return asStringList(jsonDecode(value));
    } catch (_) {}
  }
  if (value is String && value.isNotEmpty) return <String>[value];
  return asList(value)
      .where((item) => item != null)
      .map((item) => '$item')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

/// Short, non-sensitive description of a payload's shape for diagnostics.
String describeShape(dynamic value, {int depth = 0}) {
  if (value is Map) {
    if (depth > 1) return '{…}';
    final keys = value.keys.take(12).map((key) {
      return '$key:${describeShape(value[key], depth: depth + 1)}';
    }).join(',');
    return '{$keys${value.length > 12 ? ',…' : ''}}';
  }
  if (value is List) {
    if (value.isEmpty) return '[]';
    return '[${value.length}×${describeShape(value.first, depth: depth + 1)}]';
  }
  if (value == null) return 'null';
  return value.runtimeType.toString();
}
