# API Inspector

Debug-only API observer for Flutter development.

The project uses Flutter's official VM Service channel to move API logs from a
running Flutter app to a desktop dashboard or an HTTP API. It targets macOS
and Windows for the desktop tool.

## Packages

- `packages/api_observer_flutter`: Flutter SDK. Add this to your app and install
  `ApiObserverDioInterceptor` on Dio.
- `packages/api_inspector_cli`: Dart CLI plus stdio MCP server.
- `apps/api_inspector_desktop`: Flutter desktop dashboard for macOS and Windows with built-in HTTP API.
- `examples/flutter_demo`: Demo app that emits requests and one contract
  violation.

## Flutter App Setup

```dart
if (!kReleaseMode) {
  ApiObserver.instance.configure(
    validator: ApiContractValidator([
      ApiContractRule(
        method: 'GET',
        pathPattern: '/user/profile',
        fields: [
          FieldRule('data.id', type: FieldType.integer, required: true, nullable: false),
          FieldRule('data.nickname', type: FieldType.string, maxLength: 20),
        ],
      ),
    ]),
  );
  ApiObserver.instance.registerVmServiceExtensions();
}

dio.interceptors.add(ApiObserverDioInterceptor());
```

Only enable this in debug/profile builds. The package returns redacted data by
default for keys such as `Authorization`, `Cookie`, `token`, `password`, and
`phone`.

## Run From The Desktop App

Start the desktop dashboard:

```bash
cd apps/api_inspector_desktop
flutter run -d macos
```

Use `flutter run -d windows` on Windows.

In the `Run` page:

1. Set `Flutter project directory` to the app you want to debug.
2. Select an Android emulator, iOS simulator, macOS, or Windows device.
3. Click `Run`.

The desktop app runs `flutter run -d <device>`, watches the output, extracts the
VM Service URL, and connects automatically. The `Traffic` page then behaves like
a packet-capture view with request list, details, response body, cURL, timing,
errors, and contract violations.

Manual URL connection is still available from `Settings`.

## Run The Demo

Terminal:

```bash
cd apps/api_inspector_desktop
flutter run -d macos
```

Then set the project directory to `examples/flutter_demo`, choose a device, and
click `Run`. Press the buttons in the demo app to emit traffic.

## HTTP API

When the desktop app starts, an HTTP API server is available at `http://localhost:8080`.

### Available Endpoints

```
GET /api/spec         # OpenAPI specification
GET /api/logs         # Query API request logs
GET /api/logs/:id     # Get single request detail
GET /api/violations   # List contract violations
GET /api/status       # Server status
```

### Examples

```bash
# Check server status
curl http://localhost:8080/api/status

# Get API specification
curl http://localhost:8080/api/spec

# Query logs
curl "http://localhost:8080/api/logs?limit=10"
curl "http://localhost:8080/api/logs?query=user&onlyErrors=true"

# Get request detail
curl http://localhost:8080/api/logs/req_xxx

# List violations
curl http://localhost:8080/api/violations
```

The API serves JSON responses with CORS enabled for cross-origin requests.

## CLI Usage

```bash
cd packages/api_inspector_cli
dart run bin/api_inspector_cli.dart ping --vm-service http://127.0.0.1:xxxxx/yyyy=/
dart run bin/api_inspector_cli.dart list --vm-service http://127.0.0.1:xxxxx/yyyy=/
dart run bin/api_inspector_cli.dart detail --vm-service http://127.0.0.1:xxxxx/yyyy=/ --id req_xxx
dart run bin/api_inspector_cli.dart violations --vm-service http://127.0.0.1:xxxxx/yyyy=/
```

## MCP Usage

Run the CLI in MCP mode and pass the same VM Service URL:

```bash
dart run bin/api_inspector_cli.dart mcp --vm-service http://127.0.0.1:xxxxx/yyyy=/
```

Available tools:

- `search_api_logs`
- `get_request_detail`
- `list_contract_violations`

## Current Scope

Implemented:

- Dio request/response/error capture
- Redaction
- In-memory ring buffer
- Contract validation
- Flutter VM Service extension
- Dart CLI
- stdio MCP server
- Flutter desktop dashboard for macOS/Windows
- **Built-in HTTP API server for AI integration**

Next useful additions:

- Automatic VM Service URL discovery
- Persistent sessions
- Schema diff across samples
- VS Code extension wrapper
