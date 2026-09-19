/// Matches JSON values while ignoring null object fields, as the server does.
bool sameImportRecord(Object? a, Object? b) {
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    return keys.every((key) => sameImportRecord(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameImportRecord(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
