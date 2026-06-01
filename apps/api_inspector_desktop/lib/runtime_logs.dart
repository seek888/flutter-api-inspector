class RuntimeLogEntry {
  const RuntimeLogEntry({
    required this.id,
    required this.sequence,
    required this.timestamp,
    required this.ingestedAt,
    required this.source,
    required this.level,
    required this.type,
    required this.message,
    this.runId,
    this.stream,
    this.raw,
    this.context = const <String, Object?>{},
    this.error,
  });

  final String id;
  final int sequence;
  final DateTime timestamp;
  final DateTime ingestedAt;
  final String source;
  final String level;
  final String type;
  final String message;
  final String? runId;
  final String? stream;
  final String? raw;
  final Map<String, Object?> context;
  final Map<String, Object?>? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'sequence': sequence,
      'timestamp': timestamp.toIso8601String(),
      'ingestedAt': ingestedAt.toIso8601String(),
      'runId': runId,
      'source': source,
      'stream': stream,
      'level': level,
      'type': type,
      'message': message,
      'raw': raw,
      'context': context,
      'error': error,
    };
  }
}

class RuntimeLogQuery {
  const RuntimeLogQuery({
    this.query,
    this.from,
    this.to,
    this.sinceMs,
    this.sources = const <String>{},
    this.levels = const <String>{},
    this.types = const <String>{},
    this.stream,
    this.runId,
    this.afterSequence,
    this.limit = 100,
    this.order = RuntimeLogOrder.desc,
  });

  final String? query;
  final DateTime? from;
  final DateTime? to;
  final int? sinceMs;
  final Set<String> sources;
  final Set<String> levels;
  final Set<String> types;
  final String? stream;
  final String? runId;
  final int? afterSequence;
  final int limit;
  final RuntimeLogOrder order;
}

enum RuntimeLogOrder { asc, desc }

class RuntimeLogStore {
  RuntimeLogStore({this.capacity = 5000});

  final int capacity;
  final List<RuntimeLogEntry> _entries = <RuntimeLogEntry>[];
  int _sequence = 0;
  String? _currentRunId;

  String? get currentRunId => _currentRunId;
  int get count => _entries.length;
  int get latestSequence => _entries.isEmpty ? 0 : _entries.last.sequence;

  String startRun({String? projectPath, String? deviceId}) {
    _currentRunId = _newRunId();
    final context = <String, Object?>{};
    if (projectPath != null) {
      context['projectPath'] = projectPath;
    }
    if (deviceId != null) {
      context['deviceId'] = deviceId;
    }
    add(
      source: 'console',
      level: 'info',
      type: 'lifecycle',
      message: 'flutter run started',
      runId: _currentRunId,
      context: context,
    );
    return _currentRunId!;
  }

  void endRun(int exitCode) {
    add(
      source: 'console',
      level: exitCode == 0 ? 'info' : 'error',
      type: 'lifecycle',
      message: 'flutter run exited with code $exitCode',
      runId: _currentRunId,
      context: <String, Object?>{'exitCode': exitCode},
    );
  }

  RuntimeLogEntry add({
    required String source,
    required String level,
    required String type,
    required String message,
    String? runId,
    String? stream,
    DateTime? timestamp,
    String? raw,
    Map<String, Object?> context = const <String, Object?>{},
    Map<String, Object?>? error,
  }) {
    final now = DateTime.now();
    _sequence += 1;
    final entry = RuntimeLogEntry(
      id: 'log_${now.microsecondsSinceEpoch}_$_sequence',
      sequence: _sequence,
      timestamp: timestamp ?? now,
      ingestedAt: now,
      runId: runId ?? _currentRunId,
      source: source,
      stream: stream,
      level: level,
      type: type,
      message: message,
      raw: raw,
      context: context,
      error: error,
    );
    _entries.add(entry);
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    return entry;
  }

  RuntimeLogEntry? getById(String id) {
    for (final entry in _entries) {
      if (entry.id == id) {
        return entry;
      }
    }
    return null;
  }

  List<RuntimeLogEntry> search(RuntimeLogQuery query) {
    Iterable<RuntimeLogEntry> result = _entries;
    final from = query.from ?? _sinceToFrom(query.sinceMs);
    if (from != null) {
      result = result.where((entry) => !entry.timestamp.isBefore(from));
    }
    final to = query.to;
    if (to != null) {
      result = result.where((entry) => !entry.timestamp.isAfter(to));
    }
    if (query.afterSequence != null) {
      result = result.where((entry) => entry.sequence > query.afterSequence!);
    }
    if (query.sources.isNotEmpty) {
      result = result.where((entry) => query.sources.contains(entry.source));
    }
    if (query.levels.isNotEmpty) {
      result = result.where((entry) => query.levels.contains(entry.level));
    }
    if (query.types.isNotEmpty) {
      result = result.where((entry) => query.types.contains(entry.type));
    }
    if (query.stream != null && query.stream!.isNotEmpty) {
      result = result.where((entry) => entry.stream == query.stream);
    }
    if (query.runId != null && query.runId!.isNotEmpty) {
      result = result.where((entry) => entry.runId == query.runId);
    }
    final needle = query.query?.trim().toLowerCase();
    if (needle != null && needle.isNotEmpty) {
      result = result.where((entry) => _matches(entry, needle));
    }
    final ordered = query.order == RuntimeLogOrder.asc
        ? result
        : result.toList(growable: false).reversed;
    final limit = query.limit.clamp(1, capacity);
    return ordered.take(limit).toList(growable: false);
  }

  Map<String, Object?> context({
    required String id,
    int before = 100,
    int after = 50,
  }) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      return <String, Object?>{'target': null, 'entries': <Object?>[]};
    }
    final beforeCount = before.clamp(0, capacity);
    final afterCount = after.clamp(0, capacity);
    final start = (index - beforeCount).clamp(0, _entries.length);
    final end = (index + afterCount + 1).clamp(0, _entries.length);
    return <String, Object?>{
      'target': _entries[index].toJson(),
      'entries': _entries
          .sublist(start, end)
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  void clear() {
    _entries.clear();
  }

  bool _matches(RuntimeLogEntry entry, String needle) {
    return entry.message.toLowerCase().contains(needle) ||
        (entry.raw ?? '').toLowerCase().contains(needle) ||
        entry.source.toLowerCase().contains(needle) ||
        entry.level.toLowerCase().contains(needle) ||
        entry.type.toLowerCase().contains(needle) ||
        (entry.stream ?? '').toLowerCase().contains(needle) ||
        (entry.error?['message']?.toString().toLowerCase().contains(needle) ??
            false) ||
        (entry.error?['stackTrace']?.toString().toLowerCase().contains(
              needle,
            ) ??
            false);
  }

  DateTime? _sinceToFrom(int? sinceMs) {
    if (sinceMs == null || sinceMs <= 0) {
      return null;
    }
    return DateTime.now().subtract(Duration(milliseconds: sinceMs));
  }

  String _newRunId() {
    return 'run_${DateTime.now().microsecondsSinceEpoch}';
  }
}

Set<String> parseCsvSet(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const <String>{};
  }
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}
