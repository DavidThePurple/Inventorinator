import 'dart:convert';

class WorkshopMergeConflict implements Exception {
  const WorkshopMergeConflict(this.path);

  final String path;

  @override
  String toString() => 'Both devices changed $path differently.';
}

const _missing = _MissingValue();

class _MissingValue {
  const _MissingValue();
}

Object? _sortedJson(Object? value) {
  if (value is List) return value.map(_sortedJson).toList();
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortedJson(value[key])};
  }
  return value;
}

bool _sameJson(Object? left, Object? right) {
  if (identical(left, _missing) || identical(right, _missing)) {
    return identical(left, right);
  }
  return jsonEncode(_sortedJson(left)) == jsonEncode(_sortedJson(right));
}

String canonicalWorkshopState(String source) =>
    jsonEncode(_sortedJson(jsonDecode(source)));

bool _isIdList(Object? value) =>
    identical(value, _missing) ||
    value is List &&
        value.every(
          (entry) => entry is Map<String, dynamic> && entry['id'] is String,
        );

Map<String, Object?> _indexRows(Object? value) {
  if (identical(value, _missing)) return const {};
  return {
    for (final row in (value as List).cast<Map<String, dynamic>>())
      row['id'] as String: row,
  };
}

Object? _mergeValue(Object? base, Object? local, Object? cloud, String path) {
  if (_sameJson(local, cloud)) return local;
  if (_sameJson(local, base)) return cloud;
  if (_sameJson(cloud, base)) return local;

  if (local is Map<String, dynamic> && cloud is Map<String, dynamic>) {
    final baseMap = base is Map<String, dynamic>
        ? base
        : const <String, dynamic>{};
    final keys = {...baseMap.keys, ...local.keys, ...cloud.keys};
    final merged = <String, dynamic>{};
    for (final key in keys) {
      final value = _mergeValue(
        baseMap.containsKey(key) ? baseMap[key] : _missing,
        local.containsKey(key) ? local[key] : _missing,
        cloud.containsKey(key) ? cloud[key] : _missing,
        '$path.$key',
      );
      if (!identical(value, _missing)) merged[key] = value;
    }
    return merged;
  }

  if (_isIdList(base) && _isIdList(local) && _isIdList(cloud)) {
    final baseRows = _indexRows(base);
    final localRows = _indexRows(local);
    final cloudRows = _indexRows(cloud);
    final ids = {...baseRows.keys, ...localRows.keys, ...cloudRows.keys};
    final merged = <Object?>[];
    for (final id in ids) {
      final value = _mergeValue(
        baseRows[id] ?? _missing,
        localRows[id] ?? _missing,
        cloudRows[id] ?? _missing,
        '$path[$id]',
      );
      if (!identical(value, _missing)) merged.add(value);
    }
    return merged;
  }

  throw WorkshopMergeConflict(path);
}

/// Three-way merges complete workshop documents without dropping unknown or
/// newly added sections. An irreconcilable same-field edit is rejected rather
/// than silently choosing a device and losing the other value.
String mergeWorkshopStates(String base, String local, String cloud) {
  final merged = _mergeValue(
    jsonDecode(base),
    jsonDecode(local),
    jsonDecode(cloud),
    'workshop',
  );
  return jsonEncode(_sortedJson(merged));
}
