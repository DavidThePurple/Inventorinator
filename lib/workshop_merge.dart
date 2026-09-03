import 'dart:convert';

Object? _sortedJson(Object? value) {
  if (value is List) return value.map(_sortedJson).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortedJson(value[key])};
  }
  return value;
}

String canonicalWorkshopState(String source) =>
    jsonEncode(_sortedJson(jsonDecode(source)));
