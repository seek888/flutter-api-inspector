import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:api_inspector_cli/api_inspector_cli.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// HTTP API 服务器，为 AI 提供查询接口
class ApiInspectorHttpServer {
  ApiInspectorHttpServer({this.host = 'localhost', this.port = 8080});

  final String host;
  final int port;
  HttpServer? _server;
  ApiInspectorClient? _client;

  /// 启动 HTTP 服务器
  Future<void> start() async {
    final router = Router()
      ..get('/api/spec', _handleSpec)
      ..get('/api/logs', _handleLogs)
      ..get('/api/logs/<id>', _handleLogDetail)
      ..get('/api/violations', _handleViolations)
      ..get('/api/status', _handleStatus);

    final handler = Pipeline()
        .addMiddleware(_logRequests())
        .addMiddleware(_corsHeaders())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
    developer.log(
      'API Inspector HTTP server started on http://$host:$port',
      name: 'api_inspector_desktop.http_server',
    );
  }

  /// 停止服务器
  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  /// 设置当前连接的 API Inspector 客户端
  void setClient(ApiInspectorClient? client) {
    _client = client;
  }

  /// CORS 中间件
  Middleware _corsHeaders() {
    return (Handler innerHandler) {
      return (Request request) async {
        final response = await innerHandler(request);
        return response.change(
          headers: {
            ...response.headers,
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          },
        );
      };
    };
  }

  /// 日志中间件
  Middleware _logRequests() {
    return (Handler innerHandler) {
      return (Request request) {
        developer.log(
          '${request.method} ${request.url.path}',
          name: 'api_inspector_desktop.http_server',
        );
        return innerHandler(request);
      };
    };
  }

  /// GET /api/spec - 返回 OpenAPI 格式的 API 描述
  Future<Response> _handleSpec(Request request) async {
    final spec = {
      'openapi': '3.0.0',
      'info': {
        'title': 'API Inspector',
        'version': '1.0.0',
        'description': 'HTTP API for querying Flutter app request logs',
      },
      'servers': [
        {'url': 'http://$host:$port', 'description': 'Local server'},
      ],
      'paths': {
        '/api/logs': {
          'get': {
            'summary': 'Query API request logs',
            'description':
                'Get a list of captured API requests with optional filtering',
            'parameters': [
              {
                'name': 'query',
                'in': 'query',
                'description': 'Search keyword for path or method',
                'schema': {'type': 'string'},
              },
              {
                'name': 'limit',
                'in': 'query',
                'description': 'Maximum number of results (default: 30)',
                'schema': {'type': 'integer', 'default': 30},
              },
              {
                'name': 'onlyErrors',
                'in': 'query',
                'description': 'Only return requests with errors',
                'schema': {'type': 'boolean'},
              },
              {
                'name': 'onlyViolations',
                'in': 'query',
                'description': 'Only return requests with contract violations',
                'schema': {'type': 'boolean'},
              },
            ],
            'responses': {
              '200': {
                'description': 'List of request summaries',
                'content': {
                  'application/json': {
                    'schema': {
                      'type': 'array',
                      'items': {'\$ref': '#/components/schemas/RequestSummary'},
                    },
                  },
                },
              },
            },
          },
        },
        '/api/logs/{id}': {
          'get': {
            'summary': 'Get single request detail',
            'description': 'Get full details of a specific request by ID',
            'parameters': [
              {
                'name': 'id',
                'in': 'path',
                'required': true,
                'description': 'Request ID (e.g., req_xxx)',
                'schema': {'type': 'string'},
              },
            ],
            'responses': {
              '200': {
                'description': 'Request detail',
                'content': {
                  'application/json': {
                    'schema': {'\$ref': '#/components/schemas/RequestDetail'},
                  },
                },
              },
            },
          },
        },
        '/api/violations': {
          'get': {
            'summary': 'List contract violations',
            'description':
                'Get all API requests that have contract validation violations',
            'responses': {
              '200': {'description': 'List of violations'},
            },
          },
        },
        '/api/status': {
          'get': {
            'summary': 'Server status',
            'description': 'Get current server and connection status',
            'responses': {
              '200': {'description': 'Status information'},
            },
          },
        },
      },
      'components': {
        'schemas': {
          'RequestSummary': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': 'Unique request ID'},
              'method': {'type': 'string', 'example': 'GET'},
              'path': {'type': 'string', 'example': '/api/users'},
              'statusCode': {'type': 'integer', 'nullable': true},
              'durationMs': {'type': 'integer', 'nullable': true},
              'hasError': {'type': 'boolean'},
              'hasViolation': {'type': 'boolean'},
              'startedAt': {'type': 'string', 'format': 'date-time'},
            },
          },
          'RequestDetail': {
            'type': 'object',
            'description':
                'Full request/response details including headers, body, timing, etc.',
          },
        },
      },
    };
    return Response.ok(
      jsonEncode(spec),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/logs - 查询日志列表
  Future<Response> _handleLogs(Request request) async {
    final client = _client;
    if (client == null) {
      return _serviceUnavailable('Not connected to Flutter app');
    }

    try {
      final params = request.url.queryParameters;
      final logs = await client.listRequests(
        query: params['query'],
        limit: int.tryParse(params['limit'] ?? '') ?? 30,
        onlyErrors: params['onlyErrors'] == 'true',
        onlyViolations: params['onlyViolations'] == 'true',
      );

      return Response.ok(
        jsonEncode(logs.map((l) => l.toJson()).toList()),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _jsonHeaders,
      );
    }
  }

  /// GET /api/logs/:id - 获取单条详情
  Future<Response> _handleLogDetail(Request request) async {
    final client = _client;
    if (client == null) {
      return _serviceUnavailable('Not connected to Flutter app');
    }

    final id = request.params['id'];
    if (id == null || id.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing request id'}),
        headers: _jsonHeaders,
      );
    }

    try {
      final detail = await client.getRequest(id);
      if (detail == null) {
        return Response.notFound(
          jsonEncode({'error': 'Request not found: $id'}),
          headers: _jsonHeaders,
        );
      }
      return Response.ok(jsonEncode(detail), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _jsonHeaders,
      );
    }
  }

  /// GET /api/violations - 获取违规记录
  Future<Response> _handleViolations(Request request) async {
    final client = _client;
    if (client == null) {
      return _serviceUnavailable('Not connected to Flutter app');
    }

    try {
      final violations = await client.listViolations();
      return Response.ok(jsonEncode(violations), headers: _jsonHeaders);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _jsonHeaders,
      );
    }
  }

  /// GET /api/status - 服务状态
  Future<Response> _handleStatus(Request request) async {
    final status = {
      'server': 'running',
      'connected': _client != null,
      'endpoints': [
        'GET /api/spec',
        'GET /api/logs',
        'GET /api/logs/:id',
        'GET /api/violations',
        'GET /api/status',
      ],
    };
    return Response.ok(jsonEncode(status), headers: _jsonHeaders);
  }

  Response _serviceUnavailable(String message) {
    return Response(
      503,
      body: jsonEncode({'error': message}),
      headers: _jsonHeaders,
    );
  }

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };
}
