import 'models.dart';

class ApiLogStore {
  ApiLogStore({this.capacity = 1000});

  final int capacity;
  final List<ApiLogEntry> _entries = <ApiLogEntry>[];

  void add(ApiLogEntry entry) {
    _entries.removeWhere((item) => item.id == entry.id);
    _entries.insert(0, entry);
    while (_entries.length > capacity) {
      _entries.removeLast();
    }
  }

  void update(String id, ApiLogEntry Function(ApiLogEntry entry) updater) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      return;
    }
    _entries[index] = updater(_entries[index]);
  }

  ApiLogEntry? getById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  List<ApiLogEntry> list({
    String? query,
    bool onlyErrors = false,
    bool onlyViolations = false,
    int offset = 0,
    int limit = 100,
  }) {
    Iterable<ApiLogEntry> result = _entries;
    if (query != null && query.trim().isNotEmpty) {
      final normalized = query.toLowerCase();
      result = result.where((entry) {
        return entry.uri.toLowerCase().contains(normalized) ||
            entry.method.toLowerCase().contains(normalized) ||
            (entry.error ?? '').toLowerCase().contains(normalized);
      });
    }
    if (onlyErrors) {
      result = result.where((entry) => entry.hasError);
    }
    if (onlyViolations) {
      result = result.where((entry) => entry.hasViolation);
    }
    return result.skip(offset).take(limit).toList(growable: false);
  }

  List<ApiLogEntry> get violations {
    return _entries
        .where((entry) => entry.hasViolation)
        .toList(growable: false);
  }

  void clear() {
    _entries.clear();
  }
}
