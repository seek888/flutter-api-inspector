import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_inspector_cli/api_inspector_cli.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'http_server.dart';

late final ApiInspectorHttpServer _httpServer;

void main() {
  // 启动 HTTP 服务器
  _httpServer = ApiInspectorHttpServer();
  // 使用 unawaited 避免警告，服务器会异步启动
  unawaited(_httpServer.start());
  runApp(const ApiInspectorApp());
}

class ApiInspectorApp extends StatelessWidget {
  const ApiInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'API Inspector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6f73),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        listTileTheme: const ListTileThemeData(dense: true),
      ),
      home: const DashboardPage(),
    );
  }
}

enum AppSection { run, traffic, violations, settings }

class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  final String name;
  final String platform;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TextEditingController _projectController = TextEditingController(
    text: kIsWeb ? '' : Directory.current.path,
  );
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _consoleController = ScrollController();

  AppSection _section = AppSection.run;
  ApiInspectorClient? _client;
  Process? _flutterProcess;
  List<FlutterDevice> _devices = const <FlutterDevice>[];
  FlutterDevice? _selectedDevice;
  List<InspectorRequestSummary> _requests = const <InspectorRequestSummary>[];
  Map<String, Object?>? _selected;
  String? _selectedId;
  String? _vmServiceUrl;
  String? _error;
  bool _busy = false;
  bool _runningFlutter = false;
  bool _onlyErrors = false;
  bool _onlyViolations = false;
  final List<String> _console = <String>[];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDevices());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flutterProcess?.kill();
    _client?.dispose();
    _projectController.dispose();
    _urlController.dispose();
    _searchController.dispose();
    _consoleController.dispose();
    _httpServer.stop();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await Process.run('flutter', <String>[
        'devices',
        '--machine',
      ]);
      if (result.exitCode != 0) {
        throw StateError(result.stderr.toString());
      }
      final raw = jsonDecode(result.stdout.toString()) as List<dynamic>;
      final devices = raw
          .whereType<Map>()
          .map((item) {
            return FlutterDevice(
              id: item['id'] as String? ?? '',
              name: item['name'] as String? ?? '',
              platform:
                  item['targetPlatform'] as String? ??
                  item['platform'] as String? ??
                  '',
            );
          })
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _devices = devices;
        _selectedDevice = devices.isNotEmpty ? devices.first : null;
      });
    } catch (error) {
      setState(() => _error = 'flutter devices failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runFlutterApp() async {
    final device = _selectedDevice;
    if (device == null) {
      setState(() => _error = 'No Flutter device selected.');
      return;
    }
    await _stopFlutterApp();
    setState(() {
      _runningFlutter = true;
      _section = AppSection.traffic;
      _console.clear();
      _error = null;
    });
    try {
      final process = await Process.start(
        'flutter',
        <String>['run', '-d', device.id],
        workingDirectory: _projectController.text.trim(),
        runInShell: Platform.isWindows,
      );
      _flutterProcess = process;
      _listenFlutterOutput(process.stdout);
      _listenFlutterOutput(process.stderr);
      unawaited(
        process.exitCode.then((code) {
          if (!mounted) {
            return;
          }
          setState(() {
            _runningFlutter = false;
            _appendConsole('flutter run exited with code $code');
          });
        }),
      );
    } catch (error) {
      setState(() {
        _runningFlutter = false;
        _error = 'flutter run failed: $error';
      });
    }
  }

  void _listenFlutterOutput(Stream<List<int>> stream) {
    stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      _appendConsole(line);
      final url = _extractVmServiceUrl(line);
      if (url != null && url != _vmServiceUrl) {
        setState(() {
          _vmServiceUrl = url;
          _urlController.text = url;
        });
        unawaited(_connect(url));
      }
    });
  }

  String? _extractVmServiceUrl(String line) {
    final patterns = <RegExp>[
      RegExp(r'(http://127\.0\.0\.1:\d+/[^\s]+)'),
      RegExp(r'(http://localhost:\d+/[^\s]+)'),
      RegExp(r'(ws://127\.0\.0\.1:\d+/[^\s]+/ws)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  Future<void> _stopFlutterApp() async {
    _flutterProcess?.kill();
    _flutterProcess = null;
    if (mounted) {
      setState(() => _runningFlutter = false);
    }
  }

  Future<void> _connect([String? url]) async {
    final targetUrl = url ?? _urlController.text;
    if (targetUrl.trim().isEmpty) {
      setState(() => _error = 'VM Service URL is empty.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = await ApiInspectorClient.connect(targetUrl);
      await client.ping();
      await _client?.dispose();
      _client = client;
      // 设置 HTTP 服务器的 client
      _httpServer.setClient(client);
      _vmServiceUrl = targetUrl;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
      await _refresh();
    } catch (error) {
      setState(() => _error = 'Connect failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) {
      return;
    }
    try {
      final requests = await client.listRequests(
        query: _searchController.text,
        onlyErrors: _onlyErrors,
        onlyViolations: _onlyViolations,
        limit: 500,
      );
      Map<String, Object?>? selected = _selected;
      if (_selectedId != null) {
        selected = await client.getRequest(_selectedId!);
      }
      if (mounted) {
        setState(() {
          _requests = requests;
          _selected = selected;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Refresh failed: $error');
      }
    }
  }

  Future<void> _select(String id) async {
    final client = _client;
    if (client == null) {
      return;
    }
    setState(() {
      _selectedId = id;
      _busy = true;
    });
    try {
      final detail = await client.getRequest(id);
      setState(() => _selected = detail);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _clearTraffic() async {
    await _client?.clear();
    setState(() {
      _requests = const <InspectorRequestSummary>[];
      _selected = null;
      _selectedId = null;
    });
  }

  void _appendConsole(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      _console.add(text);
      if (_console.length > 1000) {
        _console.removeRange(0, _console.length - 1000);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleController.hasClients) {
        _consoleController.jumpTo(_consoleController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _section.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) =>
                setState(() => _section = AppSection.values[index]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.play_arrow),
                label: Text('Run'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.swap_vert),
                label: Text('Traffic'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.report_problem_outlined),
                label: Text('Issues'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  connected: _client != null,
                  running: _runningFlutter,
                  busy: _busy,
                  vmServiceUrl: _vmServiceUrl,
                  error: _error,
                  onRefresh: _refresh,
                  onClear: _clearTraffic,
                ),
                Expanded(child: _buildSection()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case AppSection.run:
        return RunSection(
          projectController: _projectController,
          devices: _devices,
          selectedDevice: _selectedDevice,
          busy: _busy,
          running: _runningFlutter,
          console: _console,
          consoleController: _consoleController,
          onLoadDevices: _loadDevices,
          onDeviceChanged: (device) => setState(() => _selectedDevice = device),
          onRun: _runFlutterApp,
          onStop: _stopFlutterApp,
        );
      case AppSection.traffic:
        return TrafficSection(
          requests: _requests,
          selectedId: _selectedId,
          selected: _selected,
          searchController: _searchController,
          onlyErrors: _onlyErrors,
          onlyViolations: _onlyViolations,
          onSearch: _refresh,
          onFilterChanged: ({bool? onlyErrors, bool? onlyViolations}) {
            setState(() {
              _onlyErrors = onlyErrors ?? _onlyErrors;
              _onlyViolations = onlyViolations ?? _onlyViolations;
            });
            unawaited(_refresh());
          },
          onSelected: _select,
        );
      case AppSection.violations:
        return ViolationsSection(requests: _requests, onSelected: _select);
      case AppSection.settings:
        return SettingsSection(
          urlController: _urlController,
          onConnect: () => _connect(),
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.connected,
    required this.running,
    required this.busy,
    required this.onRefresh,
    required this.onClear,
    this.vmServiceUrl,
    this.error,
  });

  final bool connected;
  final bool running;
  final bool busy;
  final String? vmServiceUrl;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              connected ? Icons.link : Icons.link_off,
              color: connected ? Colors.green.shade700 : colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(connected ? 'Connected' : 'Disconnected'),
            const SizedBox(width: 16),
            Icon(
              running ? Icons.play_circle : Icons.stop_circle_outlined,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(running ? 'Flutter running' : 'Runner idle'),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                error ?? vmServiceUrl ?? 'No VM Service connected',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: error == null
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.error,
                ),
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Clear traffic',
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class RunSection extends StatelessWidget {
  const RunSection({
    super.key,
    required this.projectController,
    required this.devices,
    required this.selectedDevice,
    required this.busy,
    required this.running,
    required this.console,
    required this.consoleController,
    required this.onLoadDevices,
    required this.onDeviceChanged,
    required this.onRun,
    required this.onStop,
  });

  final TextEditingController projectController;
  final List<FlutterDevice> devices;
  final FlutterDevice? selectedDevice;
  final bool busy;
  final bool running;
  final List<String> console;
  final ScrollController consoleController;
  final VoidCallback onLoadDevices;
  final ValueChanged<FlutterDevice?> onDeviceChanged;
  final VoidCallback onRun;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: projectController,
                  decoration: const InputDecoration(
                    labelText: 'Flutter project directory',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<FlutterDevice>(
                  initialValue: selectedDevice,
                  decoration: const InputDecoration(
                    labelText: 'Device',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: devices
                      .map(
                        (device) => DropdownMenuItem<FlutterDevice>(
                          value: device,
                          child: Text(
                            '${device.name} (${device.id})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onDeviceChanged,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Reload devices',
                onPressed: busy ? null : onLoadDevices,
                icon: const Icon(Icons.usb),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: running ? onStop : onRun,
                icon: Icon(running ? Icons.stop : Icons.play_arrow),
                label: Text(running ? 'Stop' : 'Run'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff111817),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectionArea(
                child: ListView.builder(
                  controller: consoleController,
                  padding: const EdgeInsets.all(12),
                  itemCount: console.length,
                  itemBuilder: (context, index) {
                    return Text(
                      console[index],
                      style: const TextStyle(
                        color: Color(0xffd8e6e2),
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TrafficSection extends StatelessWidget {
  const TrafficSection({
    super.key,
    required this.requests,
    required this.selectedId,
    required this.selected,
    required this.searchController,
    required this.onlyErrors,
    required this.onlyViolations,
    required this.onSearch,
    required this.onFilterChanged,
    required this.onSelected,
  });

  final List<InspectorRequestSummary> requests;
  final String? selectedId;
  final Map<String, Object?>? selected;
  final TextEditingController searchController;
  final bool onlyErrors;
  final bool onlyViolations;
  final VoidCallback onSearch;
  final void Function({bool? onlyErrors, bool? onlyViolations}) onFilterChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TrafficToolbar(
          searchController: searchController,
          onlyErrors: onlyErrors,
          onlyViolations: onlyViolations,
          onSearch: onSearch,
          onFilterChanged: onFilterChanged,
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 460,
                child: RequestList(
                  requests: requests,
                  selectedId: selectedId,
                  onSelected: onSelected,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: RequestDetail(detail: selected)),
              const VerticalDivider(width: 1),
              SizedBox(width: 320, child: IssuePanel(detail: selected)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrafficToolbar extends StatelessWidget {
  const _TrafficToolbar({
    required this.searchController,
    required this.onlyErrors,
    required this.onlyViolations,
    required this.onSearch,
    required this.onFilterChanged,
  });

  final TextEditingController searchController;
  final bool onlyErrors;
  final bool onlyViolations;
  final VoidCallback onSearch;
  final void Function({bool? onlyErrors, bool? onlyViolations}) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search path, method, or error',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('Errors'),
            selected: onlyErrors,
            onSelected: (v) => onFilterChanged(onlyErrors: v),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Violations'),
            selected: onlyViolations,
            onSelected: (v) => onFilterChanged(onlyViolations: v),
          ),
        ],
      ),
    );
  }
}

class RequestList extends StatelessWidget {
  const RequestList({
    super.key,
    required this.requests,
    required this.selectedId,
    required this.onSelected,
  });

  final List<InspectorRequestSummary> requests;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const Center(child: Text('No traffic captured'));
    }
    return Column(
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Row(
            children: [
              SizedBox(width: 54, child: Text('Method')),
              Expanded(child: Text('Path')),
              SizedBox(width: 58, child: Text('Status')),
              SizedBox(width: 62, child: Text('Time')),
              SizedBox(width: 44),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: requests.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = requests[index];
              final selected = item.id == selectedId;
              return InkWell(
                onTap: () => onSelected(item.id),
                child: Container(
                  color: selected
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.6)
                      : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Text(
                          item.method,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        child: Text(item.path, overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(
                        width: 58,
                        child: _StatusPill(
                          statusCode: item.statusCode,
                          hasError: item.hasError,
                        ),
                      ),
                      SizedBox(
                        width: 62,
                        child: Text('${item.durationMs ?? '-'}ms'),
                      ),
                      SizedBox(width: 44, child: _RequestMark(item: item)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.statusCode, required this.hasError});

  final int? statusCode;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final code = statusCode;
    final color = code == null
        ? Colors.grey
        : code >= 500
        ? Colors.red
        : code >= 400
        ? Colors.orange
        : hasError
        ? Colors.red
        : Colors.green;
    return Text(
      code?.toString() ?? '-',
      style: TextStyle(color: color.shade700, fontWeight: FontWeight.w700),
    );
  }
}

class _RequestMark extends StatelessWidget {
  const _RequestMark({required this.item});

  final InspectorRequestSummary item;

  @override
  Widget build(BuildContext context) {
    if (item.hasViolation) {
      return Badge(
        label: Text(item.violationCount.toString()),
        child: const Icon(Icons.report_problem_outlined),
      );
    }
    if (item.hasError) {
      return const Icon(Icons.error_outline);
    }
    return const Icon(Icons.check_circle_outline);
  }
}

class RequestDetail extends StatelessWidget {
  const RequestDetail({super.key, required this.detail});

  final Map<String, Object?>? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    if (detail == null) {
      return const Center(child: Text('Select a request'));
    }
    final violations = detail['violations'] as List? ?? const <Object?>[];
    return DefaultTabController(
      length: 8,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'Headers'),
                Tab(text: 'Request'),
                Tab(text: 'Response'),
                Tab(text: 'Timing'),
                Tab(text: 'Stack'),
                Tab(text: 'cURL'),
                Tab(text: 'Raw'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _JsonPanel(value: _overview(detail)),
                _JsonPanel(
                  value: {
                    'request': detail['requestHeaders'],
                    'response': detail['responseHeaders'],
                  },
                ),
                _JsonPanel(value: detail['requestBody']),
                _JsonPanel(value: detail['responseBody']),
                _JsonPanel(
                  value: {
                    'durationMs': detail['durationMs'],
                    'startedAt': detail['startedAt'],
                    'completedAt': detail['completedAt'],
                  },
                ),
                _JsonPanel(
                  value: {
                    'error': detail['error'],
                    'stackTrace': detail['stackTrace'],
                    'violations': violations,
                  },
                ),
                _TextPanel(text: _curl(detail)),
                _JsonPanel(value: detail),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Object?> _overview(Map<String, Object?> detail) {
    return <String, Object?>{
      'id': detail['id'],
      'method': detail['method'],
      'uri': detail['uri'],
      'path': detail['path'],
      'statusCode': detail['statusCode'],
      'durationMs': detail['durationMs'],
      'status': detail['status'],
      'startedAt': detail['startedAt'],
      'completedAt': detail['completedAt'],
      'hasError': detail['hasError'],
      'hasViolation': detail['hasViolation'],
    };
  }

  String _curl(Map<String, Object?> detail) {
    final method = detail['method'] ?? 'GET';
    final uri = detail['uri'] ?? '';
    final headers = detail['requestHeaders'];
    final buffer = StringBuffer('curl -X $method');
    if (headers is Map) {
      for (final entry in headers.entries) {
        buffer.write(" -H '${entry.key}: ${entry.value}'");
      }
    }
    final body = detail['requestBody'];
    if (body != null) {
      buffer.write(" --data '${jsonEncode(body)}'");
    }
    buffer.write(" '$uri'");
    return buffer.toString();
  }
}

class IssuePanel extends StatelessWidget {
  const IssuePanel({super.key, required this.detail});

  final Map<String, Object?>? detail;

  @override
  Widget build(BuildContext context) {
    final violations = detail?['violations'] as List? ?? const <Object?>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Text(
            'Issues / AI Context',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: violations.isEmpty
              ? const Center(child: Text('No contract violations'))
              : ListView.separated(
                  itemCount: violations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = (violations[index] as Map)
                        .cast<String, Object?>();
                    return ListTile(
                      leading: const Icon(Icons.report_problem_outlined),
                      title: Text(item['field']?.toString() ?? ''),
                      subtitle: Text(
                        '${item['message']}\nexpected: ${item['expected']}\nactual: ${item['actual']}',
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class ViolationsSection extends StatelessWidget {
  const ViolationsSection({
    super.key,
    required this.requests,
    required this.onSelected,
  });

  final List<InspectorRequestSummary> requests;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = requests
        .where((item) => item.hasViolation)
        .toList(growable: false);
    if (items.isEmpty) {
      return const Center(child: Text('No contract violations captured'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: Badge(
            label: Text(item.violationCount.toString()),
            child: const Icon(Icons.report_problem_outlined),
          ),
          title: Text('${item.method} ${item.path}'),
          subtitle: Text(
            '${item.statusCode ?? '-'}  ${item.durationMs ?? '-'}ms  ${item.startedAt.toLocal()}',
          ),
          onTap: () => onSelected(item.id),
        );
      },
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.urlController,
    required this.onConnect,
  });

  final TextEditingController urlController;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Manual Connection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            decoration: const InputDecoration(
              labelText: 'Flutter VM Service URL',
              hintText: 'http://127.0.0.1:xxxxx/xxxx=/',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => onConnect(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    return _TextPanel(text: const JsonEncoder.withIndent('  ').convert(value));
  }
}

class _TextPanel extends StatelessWidget {
  const _TextPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
