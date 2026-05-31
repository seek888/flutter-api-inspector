import 'package:api_observer_flutter/api_observer_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    ApiObserver.instance.configure(
      validator: ApiContractValidator(const [
        ApiContractRule(
          method: 'GET',
          pathPattern: '/users/1',
          fields: [
            FieldRule(
              'id',
              type: FieldType.integer,
              required: true,
              nullable: false,
            ),
            FieldRule(
              'name',
              type: FieldType.string,
              required: true,
              nullable: false,
              maxLength: 8,
            ),
            FieldRule(
              'email',
              type: FieldType.string,
              required: true,
              nullable: false,
            ),
          ],
        ),
      ]),
    );
    ApiObserver.instance.registerVmServiceExtensions();
  }
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'API Observer Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2f6f73)),
        useMaterial3: true,
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  late final Dio _dio = Dio(
    BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'),
  )..interceptors.add(ApiObserverDioInterceptor());

  String _message = 'Ready';

  Future<void> _fetchUser() async {
    setState(() => _message = 'Loading /users/1');
    try {
      final response = await _dio.get('/users/1');
      setState(() => _message = 'Loaded user: ${response.data['name']}');
    } catch (error) {
      setState(() => _message = error.toString());
    }
  }

  Future<void> _fetchMissing() async {
    setState(() => _message = 'Loading missing endpoint');
    try {
      await _dio.get('/not-found');
      setState(() => _message = 'Unexpected success');
    } catch (error) {
      setState(() => _message = 'Expected error: $error');
    }
  }

  Future<void> _postSample() async {
    setState(() => _message = 'Posting sample');
    try {
      final response = await _dio.post(
        '/posts',
        data: <String, Object?>{
          'title': 'hello',
          'body': 'demo',
          'userId': 1,
          'token': 'secret-token-should-be-redacted',
        },
      );
      setState(() => _message = 'Created post id: ${response.data['id']}');
    } catch (error) {
      setState(() => _message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API Observer Demo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_message, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _fetchUser,
                  icon: const Icon(Icons.person_search),
                  label: const Text('GET /users/1'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _postSample,
                  icon: const Icon(Icons.upload),
                  label: const Text('POST /posts'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _fetchMissing,
                  icon: const Icon(Icons.error_outline),
                  label: const Text('GET /not-found'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
