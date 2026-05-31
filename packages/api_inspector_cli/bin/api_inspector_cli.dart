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

void _printJson(Object? value) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
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

Options:
${parser.usage}
''');
}
