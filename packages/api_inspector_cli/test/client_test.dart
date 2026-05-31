import 'package:api_inspector_cli/api_inspector_cli.dart';
import 'package:test/test.dart';

void main() {
  test('converts VM Service HTTP URL to WebSocket URL', () {
    final uri = ApiInspectorClient.convertToWebSocketUri('http://127.0.0.1:1234/abc=/');
    expect(uri.toString(), 'ws://127.0.0.1:1234/abc=/ws');
  });

  test('extracts URL from DevTools uri parameter', () {
    final uri = ApiInspectorClient.convertToWebSocketUri(
      'http://127.0.0.1:9100?uri=http://127.0.0.1:1234/abc=/',
    );
    expect(uri.toString(), 'ws://127.0.0.1:1234/abc=/ws');
  });
}
