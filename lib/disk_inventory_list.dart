import 'dart:collection';

/// Compatibility collection for operations spanning inventory. Only IDs and
/// pending edits are retained; reads do not populate an all-inventory cache.
class DiskInventoryList<T> extends ListBase<T> {
  DiskInventoryList({
    required Iterable<String> ids,
    required this.read,
    required this.idOf,
  }) : _ids = ids.toList();
  final T Function(String) read;
  final String Function(T) idOf;
  final List<String> _ids;
  final Map<String, T> pending = {};
  final Set<String> removed = {};
  @override
  int get length => _ids.length;
  @override
  set length(int value) {
    if (value > length) throw UnsupportedError('Use add to grow inventory');
    for (final id in _ids.skip(value)) {
      removed.add(id);
      pending.remove(id);
    }
    _ids.length = value;
  }

  @override
  T operator [](int index) => pending[_ids[index]] ?? read(_ids[index]);
  @override
  void operator []=(int index, T value) {
    final id = idOf(value);
    if (_ids[index] != id) removed.add(_ids[index]);
    _ids[index] = id;
    removed.remove(id);
    pending[id] = value;
  }

  @override
  void add(T element) {
    final id = idOf(element);
    if (!_ids.contains(id)) _ids.add(id);
    removed.remove(id);
    pending[id] = element;
  }

  @override
  void addAll(Iterable<T> iterable) {
    for (final item in iterable) {
      add(item);
    }
  }

  @override
  T removeAt(int index) {
    final item = this[index];
    final id = _ids.removeAt(index);
    pending.remove(id);
    removed.add(id);
    return item;
  }

  @override
  void removeWhere(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) removeAt(i);
    }
  }

  int indexOfId(String id) => _ids.indexOf(id);
  void removeId(String id) {
    _ids.remove(id);
    pending.remove(id);
    removed.add(id);
  }

  void acknowledge(String id) {
    pending.remove(id);
    removed.remove(id);
  }
}
