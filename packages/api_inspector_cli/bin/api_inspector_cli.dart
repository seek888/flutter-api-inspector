import 'dart:convert';
import 'dart:io';

import 'package:api_inspector_cli/api_inspector_cli.dart';
import 'package:args/args.dart';

/// 添加日志输出
void _log(String message) {
  final timestamp = DateTime.now().toIso8601String();
  stderr.writeln('[$timestamp] [CLI] $message');
}

Future<void> main(List<String> arguments) async {
  _log('=== API Inspector CLI 启动 ===');
  _log('命令行参数: $arguments');
  _log('Dart 版本: ${Platform.version}');

  final parser = ArgParser()
    ..addOption(
      'vm-service',
      abbr: 'u',
      help: 'Flutter VM Service HTTP/WebSocket URL.',
    )
    ..addOption(
      'query',
      abbr: 'q',
      help: 'Filter requests by path, method, or error text.',
    )
    ..addOption('id', help: 'Request id for detail commands.')
    ..addFlag('errors', help: 'Only show failed requests.')
    ..addFlag(
      'violations',
      help: 'Only show requests with contract violations.',
    )
    ..addOption('limit', defaultsTo: '30')
    ..addFlag('help', abbr: 'h', negatable: false);

  final command = arguments.isEmpty ? 'help' : arguments.first;
  final rest = arguments.isEmpty ? <String>[] : arguments.sublist(1);
  if (command == 'logs') {
    await _handleRuntimeLogs(rest);
    return;
  }

  final options = parser.parse(rest);

  _log('解析命令: $command, 选项: ${options.options}');

  if (command == 'help' || options['help'] == true) {
    _printHelp(parser);
    return;
  }

  final vmServiceUrl = options['vm-service'] as String?;
  if (vmServiceUrl == null || vmServiceUrl.isEmpty) {
    stderr.writeln(
      'Missing --vm-service. Paste the VM Service URL printed by flutter run.',
    );
    exitCode = 64;
    return;
  }

  _log('开始连接 VM Service...');

  final client = await ApiInspectorClient.connect(vmServiceUrl);
  try {
    _log('执行命令: $command');
    switch (command) {
      case 'ping':
        _printJson(await client.ping());
      case 'list':
        final items = await client.listRequests(
          query: options['query'] as String?,
          onlyErrors: options['errors'] as bool,
          onlyViolations: options['violations'] as bool,
          limit: int.tryParse(options['limit'] as String) ?? 30,
        );
        for (final item in items) {
          stdout.writeln(
            '${item.id} ${item.method} ${item.path} '
            '${item.statusCode ?? '-'} ${item.durationMs ?? '-'}ms '
            '${item.hasViolation ? 'violations=${item.violationCount}' : ''}',
          );
        }
      case 'detail':
        final id = options['id'] as String?;
        if (id == null) {
          throw ArgumentError('--id is required');
        }
        _printJson(await client.getRequest(id));
      case 'violations':
        _printJson(await client.listViolations());
      case 'clear':
        await client.clear();
        stdout.writeln('Cleared.');
      case 'mcp':
        _log('启动 MCP 服务器模式');
        await ApiInspectorMcpServer(client).serve();
        _log('MCP 服务器已关闭');
      default:
        stderr.writeln('Unknown command: $command');
        _printHelp(parser);
        exitCode = 64;
    }
  } catch (e, st) {
    _log('命令执行失败: $e');
    _log('堆栈: $st');
    rethrow;
  } finally {
    _log('关闭客户端连接');
    await client.dispose();
  }
}

Future<void> _handleRuntimeLogs(List<String> arguments) async {
  final command = arguments.isEmpty || arguments.first.startsWith('-')
      ? 'search'
      : arguments.first;
  final rest = arguments.isEmpty || arguments.first.startsWith('-')
      ? arguments
      : arguments.sublist(1);
  final parser = ArgParser()
    ..addOption(
      'server',
      defaultsTo: 'http://localhost:8080',
      help: 'API Inspector desktop HTTP API base URL.',
    )
    ..addOption('q', abbr: 'q', help: 'Full-text search query.')
    ..addOption('since', help: 'Relative time window, e.g. 30s, 10m, 2h.')
    ..addOption('since-ms', help: 'Relative time window in milliseconds.')
    ..addOption('from', help: 'Start time as ISO-8601.')
    ..addOption('to', help: 'End time as ISO-8601.')
    ..addOption('sources', help: 'Comma-separated sources, e.g. console,ai.')
    ..addOption('levels', help: 'Comma-separated levels, e.g. info,error.')
    ..addOption('types', help: 'Comma-separated types, e.g. log,marker.')
    ..addOption('stream', help: 'stdout or stderr.')
    ..addOption('run-id', help: 'Filter to one flutter run id.')
    ..addOption('after-sequence', help: 'Return entries after this sequence.')
    ..addOption('limit', defaultsTo: '100')
    ..addOption('order', defaultsTo: 'desc', allowed: <String>['asc', 'desc'])
    ..addOption('id', help: 'Runtime log id for detail/context commands.')
    ..addOption('before', defaultsTo: '100')
    ..addOption('after', defaultsTo: '50')
    ..addOption('message', abbr: 'm', help: 'Marker message.')
    ..addFlag('jsonl', help: 'Print tail results as NDJSON.', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final options = parser.parse(rest);
  if (command == 'help' || options['help'] == true) {
    _printLogsHelp(parser);
    return;
  }

  final server = options['server'] as String;
  switch (command) {
    case 'status':
      _printJson(await _getJson(_apiUri(server, '/api/status')));
    case 'search':
      _printJson(
        await _getJson(
          _apiUri(server, '/api/runtime-logs', {
            'q': options['q'] as String?,
            'sinceMs':
                options['since-ms'] as String? ??
                _parseDurationMs(options['since'] as String?)?.toString(),
            'from': options['from'] as String?,
            'to': options['to'] as String?,
            'sources': options['sources'] as String?,
            'levels': options['levels'] as String?,
            'types': options['types'] as String?,
            'stream': options['stream'] as String?,
            'runId': options['run-id'] as String?,
            'afterSequence': options['after-sequence'] as String?,
            'limit': options['limit'] as String?,
            'order': options['order'] as String?,
          }),
        ),
      );
    case 'tail':
      final data = await _getJson(
        _apiUri(server, '/api/runtime-logs', {
          'afterSequence': options['after-sequence'] as String?,
          'limit': options['limit'] as String?,
          'order': 'asc',
        }),
      );
      if (options['jsonl'] as bool) {
        final entries =
            (data as Map<String, Object?>)['entries'] as List? ??
            const <Object?>[];
        for (final entry in entries) {
          stdout.writeln(jsonEncode(entry));
        }
      } else {
        _printJson(data);
      }
    case 'detail':
      final id = options['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ArgumentError('--id is required');
      }
      _printJson(await _getJson(_apiUri(server, '/api/runtime-logs/$id')));
    case 'context':
      final id = options['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ArgumentError('--id is required');
      }
      _printJson(
        await _getJson(
          _apiUri(server, '/api/runtime-logs/context', {
            'id': id,
            'before': options['before'] as String?,
            'after': options['after'] as String?,
          }),
        ),
      );
    case 'mark':
      final message =
          options['message'] as String? ?? options.rest.join(' ').trim();
      if (message.isEmpty) {
        throw ArgumentError('Marker message is required');
      }
      _printJson(
        await _postJson(
          _apiUri(server, '/api/runtime-logs/markers'),
          <String, Object?>{'message': message},
        ),
      );
    default:
      stderr.writeln('Unknown logs command: $command');
      _printLogsHelp(parser);
      exitCode = 64;
  }
}

void _printJson(Object? value) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
}

Future<Object?> _getJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return await _decodeJsonResponse(uri, response);
  } finally {
    client.close(force: true);
  }
}

Future<Object?> _postJson(Uri uri, Object? body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return await _decodeJsonResponse(uri, response);
  } finally {
    client.close(force: true);
  }
}

Future<Object?> _decodeJsonResponse(
  Uri uri,
  HttpClientResponse response,
) async {
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'HTTP ${response.statusCode} from $uri: $body',
      uri: uri,
    );
  }
  if (body.trim().isEmpty) {
    return null;
  }
  return jsonDecode(body);
}

Uri _apiUri(
  String server,
  String path, [
  Map<String, String?> query = const {},
]) {
  final base = Uri.parse(server);
  final queryParameters = <String, String>{};
  for (final entry in query.entries) {
    final value = entry.value;
    if (value != null && value.isNotEmpty) {
      queryParameters[entry.key] = value;
    }
  }
  return base.replace(
    path: path,
    queryParameters: queryParameters.isEmpty ? null : queryParameters,
  );
}

int? _parseDurationMs(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(value.trim());
  if (match == null) {
    throw ArgumentError('Invalid duration: $value');
  }
  final amount = int.parse(match.group(1)!);
  return switch (match.group(2) ?? 'ms') {
    'ms' => amount,
    's' => amount * 1000,
    'm' => amount * 60 * 1000,
    'h' => amount * 60 * 60 * 1000,
    _ => amount,
  };
}

void _printHelp(ArgParser parser) {
  stdout.writeln('''
API Inspector CLI

Commands:
  ping          Test VM Service connection and extension registration
  list          List captured API requests
  detail        Print one request detail, requires --id
  violations    Print requests with contract violations
  clear         Clear captured requests in the app
  mcp           Run stdio MCP server
  logs          Query desktop runtime logs through local HTTP API

Options:
${parser.usage}
''');
}

void _printLogsHelp(ArgParser parser) {
  stdout.writeln('''
API Inspector runtime log commands

Commands:
  logs status       Print desktop API status
  logs search       Search runtime logs
  logs tail         Print recent runtime logs; use --jsonl for NDJSON
  logs detail       Print one runtime log entry, requires --id
  logs context      Print logs around one entry, requires --id
  logs mark         Write an AI/debug marker

Examples:
  api_inspector_cli logs search --since 10m --levels error
  api_inspector_cli logs context --id log_xxx --before 100 --after 50
  api_inspector_cli logs mark "start debugging login timeout"

Options:
${parser.usage}
''');
}
