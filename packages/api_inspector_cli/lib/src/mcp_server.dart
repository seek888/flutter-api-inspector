import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'inspector_client.dart';

class ApiInspectorMcpServer {
  ApiInspectorMcpServer(this.client);

  final ApiInspectorClient client;

  /// 添加日志输出
  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    stderr.writeln('[$timestamp] [McpServer] $message');
  }

  Future<void> serve() async {
    _log('MCP 服务器启动, 等待 stdin 输入...');
    try {
      await for (final line
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) {
          _log('收到空行, 跳过');
          continue;
        }
        _log('收到请求: ${line.length} 字符');
        try {
          final request = jsonDecode(line) as Map<String, Object?>;
          _log('解析请求成功: ${request['method']}');
          final response = await _handle(request);
          final responseJson = jsonEncode(response);
          stdout.writeln(responseJson);
          _log('发送响应成功: ${response['error'] != null ? '有错误' : '成功'}');
        } catch (e, st) {
          _log('处理请求失败: $e');
          _log('堆栈: $st');
          // 发送错误响应
          final errorResponse = <String, Object?>{
            'jsonrpc': '2.0',
            'id': null,
            'error': <String, Object?>{
              'code': -32700,
              'message': 'Parse error: $e',
            },
          };
          stdout.writeln(jsonEncode(errorResponse));
        }
      }
      _log('stdin 流已关闭');
    } catch (e, st) {
      _log('MCP 服务异常: $e');
      _log('堆栈: $st');
      rethrow;
    }
  }

  Future<Map<String, Object?>> _handle(Map<String, Object?> request) async {
    final id = request['id'];
    final method = request['method'] as String?;
    try {
      if (method == 'initialize') {
        return _result(id, <String, Object?>{
          'protocolVersion': '2024-11-05',
          'serverInfo': <String, Object?>{
            'name': 'api-inspector',
            'version': '0.1.0',
          },
          'capabilities': <String, Object?>{'tools': <String, Object?>{}},
        });
      }
      if (method == 'tools/list') {
        return _result(id, <String, Object?>{
          'tools': <Object?>[
            _tool('search_api_logs', 'Search captured API request summaries.'),
            _tool('get_request_detail', 'Get one captured API request by id.'),
            _tool(
              'list_contract_violations',
              'List API contract validation failures.',
            ),
          ],
        });
      }
      if (method == 'tools/call') {
        final params =
            request['params'] as Map<String, Object?>? ??
            const <String, Object?>{};
        final name = params['name'] as String?;
        final args =
            params['arguments'] as Map<String, Object?>? ??
            const <String, Object?>{};
        final data = await _callTool(name, args);
        return _result(id, <String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'text',
              'text': const JsonEncoder.withIndent('  ').convert(data),
            },
          ],
        });
      }
      return _result(id, <String, Object?>{});
    } catch (error) {
      return <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': -32000, 'message': error.toString()},
      };
    }
  }

  Future<Object?> _callTool(String? name, Map<String, Object?> args) async {
    _log('调用工具: $name, 参数: $args');
    try {
      switch (name) {
        case 'search_api_logs':
          final requests = await client.listRequests(
            query: args['query'] as String?,
            onlyErrors: args['onlyErrors'] as bool? ?? false,
            onlyViolations: args['onlyViolations'] as bool? ?? false,
            limit: args['limit'] as int? ?? 30,
          );
          _log('search_api_logs 返回 ${requests.length} 条结果');
          return requests.map((item) => item.toJson()).toList();
        case 'get_request_detail':
          final id = args['id'] as String?;
          if (id == null) {
            throw ArgumentError('id is required');
          }
          _log('获取请求详情: $id');
          return client.getRequest(id);
        case 'list_contract_violations':
          final violations = await client.listViolations();
          _log('list_contract_violations 返回 ${violations.length} 条结果');
          return violations;
        default:
          _log('未知工具: $name');
          throw ArgumentError('Unknown tool: $name');
      }
    } catch (e, st) {
      _log('工具调用失败 ($name): $e');
      _log('堆栈: $st');
      rethrow;
    }
  }

  Map<String, Object?> _tool(String name, String description) {
    return <String, Object?>{
      'name': name,
      'description': description,
      'inputSchema': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    };
  }

  Map<String, Object?> _result(Object? id, Object? result) {
    return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
  }
}
