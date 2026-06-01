import 'dart:convert';
import 'dart:io';

import 'package:api_inspector_desktop/http_server.dart';
import 'package:api_inspector_desktop/runtime_logs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serves runtime log search and marker endpoints', () async {
    final store = RuntimeLogStore();
    store.add(
      source: 'console',
      stream: 'stderr',
      level: 'error',
      type: 'log',
      message: 'DioException: timeout',
    );

    final server = ApiInspectorHttpServer(
      runtimeLogs: store,
      host: '127.0.0.1',
      port: 0,
    );
    await server.start();
    addTearDown(server.stop);
    final baseUrl = 'http://127.0.0.1:${server.boundPort}';

    final search = await _getJson(
      Uri.parse('$baseUrl/api/runtime-logs?q=timeout'),
    );
    final entries = search['entries'] as List<Object?>;
    expect(entries, hasLength(1));

    final marker = await _postJson(
      Uri.parse('$baseUrl/api/runtime-logs/markers'),
      <String, Object?>{'message': 'start investigation'},
    );
    expect(marker['type'], 'marker');
    expect(marker['source'], 'ai');
  });
}

Future<Map<String, Object?>> _getJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return await _decodeJson(response);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _postJson(Uri uri, Object? body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return await _decodeJson(response);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _decodeJson(HttpClientResponse response) async {
  final body = await response.transform(utf8.decoder).join();
  expect(response.statusCode, inInclusiveRange(200, 299), reason: body);
  return (jsonDecode(body) as Map).cast<String, Object?>();
}
