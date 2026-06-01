import 'package:api_inspector_desktop/runtime_logs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searches runtime logs by query, level, and sequence', () {
    final store = RuntimeLogStore(capacity: 10);
    final first = store.add(
      source: 'console',
      stream: 'stdout',
      level: 'info',
      type: 'log',
      message: 'app started',
    );
    store.add(
      source: 'console',
      stream: 'stderr',
      level: 'error',
      type: 'log',
      message: 'DioException: timeout',
    );

    final results = store.search(
      RuntimeLogQuery(
        query: 'timeout',
        levels: const <String>{'error'},
        afterSequence: first.sequence,
        order: RuntimeLogOrder.asc,
      ),
    );

    expect(results, hasLength(1));
    expect(results.single.stream, 'stderr');
    expect(results.single.message, contains('timeout'));
  });

  test('returns context around a runtime log', () {
    final store = RuntimeLogStore(capacity: 10);
    store.add(source: 'console', level: 'info', type: 'log', message: 'one');
    final target = store.add(
      source: 'console',
      level: 'error',
      type: 'log',
      message: 'two',
    );
    store.add(source: 'console', level: 'info', type: 'log', message: 'three');

    final context = store.context(id: target.id, before: 1, after: 1);
    final entries = context['entries'] as List<Object?>;

    expect((context['target'] as Map<String, Object?>)['message'], 'two');
    expect(entries, hasLength(3));
  });
}
