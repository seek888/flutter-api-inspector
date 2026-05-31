import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'models.dart';

class ApiInspectorClient {
  ApiInspectorClient._(this.service, this.isolateId);

  final VmService service;
  final String isolateId;

  /// 添加日志输出
  static void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    stderr.writeln('[$timestamp] [ApiClient] $message');
  }

  static Future<ApiInspectorClient> connect(String vmServiceUri) async {
    _log('开始连接 VM Service: $vmServiceUri');
    final wsUri = convertToWebSocketUri(vmServiceUri);
    _log('转换后的 WebSocket URI: $wsUri');

    try {
      final service = await vmServiceConnectUri(wsUri.toString());
      _log('VM Service 连接成功');

      final vm = await service.getVM();
      _log('获取 VM 信息成功, isolates 数量: ${vm.isolates?.length ?? 0}');

      final isolateRef = vm.isolates?.isNotEmpty == true
          ? vm.isolates!.first
          : null;

      if (isolateRef?.id == null) {
        _log('错误: 未找到运行中的 isolate');
        throw StateError('No running isolate found for VM Service URL.');
      }

      _log('使用 isolate ID: ${isolateRef!.id}');
      return ApiInspectorClient._(service, isolateRef.id!);
    } catch (e, st) {
      _log('连接失败: $e');
      _log('堆栈: $st');
      rethrow;
    }
  }

  static Uri convertToWebSocketUri(String input) {
    var value = input.trim();
    if (value.contains('uri=')) {
      final parsed = Uri.parse(value);
      value = parsed.queryParameters['uri'] ?? value;
    }
    final uri = Uri.parse(value);
    if (uri.scheme == 'ws' || uri.scheme == 'wss') {
      return uri.path.endsWith('/ws')
          ? uri
          : uri.replace(path: _joinPath(uri.path, 'ws'));
    }
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: _joinPath(uri.path, 'ws'));
  }

  static String _joinPath(String path, String segment) {
    if (path.endsWith('/$segment')) {
      return path;
    }
    if (path.endsWith('/')) {
      return '$path$segment';
    }
    return '$path/$segment';
  }

  Future<Map<String, Object?>> ping() async {
    return _call('ext.api_observer.ping');
  }

  Future<List<InspectorRequestSummary>> listRequests({
    String? query,
    bool onlyErrors = false,
    bool onlyViolations = false,
    int offset = 0,
    int limit = 100,
  }) async {
    final result =
        await _call('ext.api_observer.listRequests', <String, String>{
          if (query != null && query.isNotEmpty) 'query': query,
          'onlyErrors': onlyErrors.toString(),
          'onlyViolations': onlyViolations.toString(),
          'offset': offset.toString(),
          'limit': limit.toString(),
        });
    final requests = result['requests'] as List? ?? const <Object?>[];
    return requests
        .whereType<Map>()
        .map(
          (item) =>
              InspectorRequestSummary.fromJson(item.cast<String, Object?>()),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>?> getRequest(String id) async {
    final result = await _call('ext.api_observer.getRequest', <String, String>{
      'id': id,
    });
    return (result['request'] as Map?)?.cast<String, Object?>();
  }

  Future<List<Map<String, Object?>>> listViolations() async {
    final result = await _call('ext.api_observer.listViolations');
    final requests = result['requests'] as List? ?? const <Object?>[];
    return requests
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  Future<void> clear() async {
    await _call('ext.api_observer.clear');
  }

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, String>? args,
  ]) async {
    _log('调用 RPC 方法: $method, 参数: $args');
    try {
      final response = await service.callServiceExtension(
        method,
        isolateId: isolateId,
        args: args,
      );
      _log('RPC 响应成功: $method');
      return response.json?.cast<String, Object?>() ??
          jsonDecode(response.toString()) as Map<String, Object?>;
    } catch (e, st) {
      _log('RPC 调用失败 ($method): $e');
      _log('堆栈: $st');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await service.dispose();
  }
}
