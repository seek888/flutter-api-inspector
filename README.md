# API Inspector

Debug-only API observer for Flutter development with built-in HTTP API for AI integration.

Monitor your Flutter app's HTTP requests in real-time with a desktop dashboard and HTTP API server.

## Features

- **Real-time API Monitoring** - View all HTTP requests in a desktop dashboard
- **Runtime Log Search** - Query Flutter run console output and AI/debug markers
- **Contract Validation** - Define API contracts and detect violations automatically
- **HTTP API Server** - Built-in `localhost:8080` API for AI integration
- **Auto-redaction** - Sensitive data (tokens, passwords) redacted by default
- **cURL Export** - Export any request as cURL command
- **Cross-platform** - macOS and Windows support

## Project Structure

```
httpcheck/
├── packages/
│   ├── api_observer_flutter/    # Flutter SDK - add to your app
│   └── api_inspector_cli/       # Dart CLI tools
├── apps/
│   └── api_inspector_desktop/   # Desktop dashboard (macOS/Windows)
└── examples/
    └── flutter_demo/            # Demo app showing integration
```

## Quick Start

### 1. Install the SDK

```bash
flutter pub add api_observer_flutter dio
```

### 2. Add to Your Flutter App

```dart
import 'package:api_observer_flutter/api_observer_flutter.dart';
import 'package:dio/dio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    // Configure optional contract validation
    ApiObserver.instance.configure(
      validator: ApiContractValidator([
        ApiContractRule(
          method: 'GET',
          pathPattern: '/user/profile',
          fields: [
            FieldRule('data.id', type: FieldType.integer, required: true),
            FieldRule('data.nickname', type: FieldType.string, maxLength: 20),
          ],
        ),
      ]),
    );
    // Register VM Service extensions
    ApiObserver.instance.registerVmServiceExtensions();
  }
  runApp(MyApp());
}

// Add the interceptor to your Dio client
final dio = Dio();
if (!kReleaseMode) {
  dio.interceptors.add(ApiObserverDioInterceptor());
}
```

### 3. Run the Desktop App

```bash
cd apps/api_inspector_desktop
flutter run -d macos    # macOS
# or
flutter run -d windows  # Windows
```

The HTTP API server starts automatically at `http://localhost:8080`.

### 4. Connect to Your App

In the desktop app:
1. **Run Tab**: Set your Flutter project path and select a device
2. Click **Run** - the app will start and connect automatically
3. **Traffic Tab**: View all API requests in real-time
4. **Issues Tab**: View contract violations

## Demo App

The demo app (`examples/flutter_demo`) shows a complete integration with:
- Contract validation (name field exceeds max length)
- Data redaction (token field)
- Error handling (404 responses)

```bash
# Terminal 1 - Start desktop app
cd apps/api_inspector_desktop
flutter run -d macos

# Terminal 2 - Run demo (or use desktop app's Run tab)
cd examples/flutter_demo
flutter run -d macos
```

**Demo Buttons:**
- **GET /users/1** - Fetches user data (contract violation: name exceeds 8 chars)
- **POST /posts** - Creates a post (shows redaction of 'token' field)
- **GET /not-found** - Triggers 404 error

## HTTP API

When the desktop app starts, an HTTP API server is available at `http://localhost:8080`.

### Available Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/spec` | OpenAPI specification - AI can auto-discover all endpoints |
| `GET /api/logs?query=&limit=30` | Query API request logs with optional filters |
| `GET /api/logs/:id` | Get single request detail by ID |
| `GET /api/violations` | List all contract violations |
| `GET /api/runtime-logs` | Search Flutter run console/runtime logs |
| `GET /api/runtime-logs/:id` | Get one runtime log entry |
| `GET /api/runtime-logs/context?id=...` | Get logs around a runtime log entry |
| `POST /api/runtime-logs/markers` | Write an AI/debug marker into runtime logs |
| `GET /api/status` | Server connection status |

### Query Parameters for `/api/logs`

| Parameter | Type | Description |
|-----------|------|-------------|
| `query` | string | Search keyword for path or method |
| `limit` | integer | Max results (default: 30) |
| `onlyErrors` | boolean | Only return requests with errors |
| `onlyViolations` | boolean | Only return requests with violations |

### Examples

```bash
# Check server status
curl http://localhost:8080/api/status

# Get API specification (for AI auto-discovery)
curl http://localhost:8080/api/spec

# Query logs
curl "http://localhost:8080/api/logs?limit=10"
curl "http://localhost:8080/api/logs?query=user&onlyErrors=true"

# Get request detail
curl http://localhost:8080/api/logs/req_xxx

# List violations
curl http://localhost:8080/api/violations

# Search runtime logs from flutter run stdout/stderr
curl "http://localhost:8080/api/runtime-logs?q=timeout&sinceMs=600000&levels=error"
curl "http://localhost:8080/api/runtime-logs?stream=stderr&limit=20&order=asc"
curl "http://localhost:8080/api/runtime-logs?sources=developer&levels=warning,error"

# Get context around a runtime log entry
curl "http://localhost:8080/api/runtime-logs/context?id=log_xxx&before=100&after=50"

# Let an AI mark the beginning of an investigation
curl -X POST http://localhost:8080/api/runtime-logs/markers \
  -H 'Content-Type: application/json' \
  -d '{"message":"start debugging login timeout"}'
```

## AI CLI Access

MCP is optional. Any AI CLI that can run shell commands can query runtime logs through the bundled CLI:

```bash
cd packages/api_inspector_cli

# Search recent Flutter console/runtime logs
dart run bin/api_inspector_cli.dart logs search --since 10m --levels error

# Tail logs as NDJSON for machine processing
dart run bin/api_inspector_cli.dart logs tail --limit 50 --jsonl

# Get context around an interesting log entry
dart run bin/api_inspector_cli.dart logs context --id log_xxx --before 100 --after 50

# Write a marker before a debugging attempt
dart run bin/api_inspector_cli.dart logs mark "start debugging login timeout"
```

Flutter app logs written through `dart:developer.log()` are captured after the
desktop app connects to the VM Service Logging stream:

```dart
import 'dart:developer' as developer;

developer.log(
  'login request timed out',
  name: 'auth.login',
  level: 1000,
  error: error,
  stackTrace: stackTrace,
);
```

## Data Redaction

The following sensitive fields are automatically redacted:
- `authorization`
- `cookie`
- `token`
- `password`
- `phone`
- `secret`

## Building Release Binaries

### macOS

```bash
cd apps/api_inspector_desktop
flutter build macos --release
# Output: build/macos/Build/Products/Release/api_inspector_desktop.app
```

### Windows

```bash
cd apps/api_inspector_desktop
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

## GitHub Setup

To push to GitHub and enable automated builds:

```bash
# Create a new repository on GitHub first, then:
git remote add origin https://github.com/YOUR_USERNAME/httpcheck.git
git branch -M main
git push -u origin main
```

Once pushed, go to the **Actions** tab to see the build progress and download release artifacts.

## License

MIT License
