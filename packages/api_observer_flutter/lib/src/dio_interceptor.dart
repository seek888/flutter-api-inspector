import 'package:dio/dio.dart';

import 'api_observer.dart';
import 'models.dart';

class ApiObserverDioInterceptor extends Interceptor {
  ApiObserverDioInterceptor({ApiObserver? observer})
    : observer = observer ?? ApiObserver.instance;

  static const String _requestIdKey = 'apiObserverRequestId';
  static const String _startedAtKey = 'apiObserverStartedAt';

  final ApiObserver observer;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final id = observer.nextId();
    final startedAt = DateTime.now();
    options.extra[_requestIdKey] = id;
    options.extra[_startedAtKey] = startedAt;
    observer.add(
      ApiLogEntry(
        id: id,
        method: options.method,
        uri: options.uri.toString(),
        path: options.uri.path,
        startedAt: startedAt,
        requestHeaders: observer.redactor.redactHeaders(options.headers),
        requestBody: observer.redactor.redact(options.data),
      ),
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _complete(response.requestOptions, response: response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _complete(
      err.requestOptions,
      response: err.response,
      error: err,
      stackTrace: err.stackTrace,
    );
    handler.next(err);
  }

  void _complete(
    RequestOptions options, {
    Response? response,
    DioException? error,
    StackTrace? stackTrace,
  }) {
    final id = options.extra[_requestIdKey] as String?;
    final startedAt = options.extra[_startedAtKey] as DateTime?;
    if (id == null || startedAt == null) {
      return;
    }
    final completedAt = DateTime.now();
    final responseBody = observer.redactor.redact(response?.data);
    final violations =
        observer.validator?.validate(
          method: options.method,
          path: options.uri.path,
          body: responseBody,
        ) ??
        const <ContractViolation>[];

    observer.update(id, (entry) {
      return entry.copyWith(
        completedAt: completedAt,
        durationMs: completedAt.difference(startedAt).inMilliseconds,
        statusCode: response?.statusCode,
        status: error == null ? ApiLogStatus.success : ApiLogStatus.error,
        responseHeaders: observer.redactor.redactHeaders(
          response?.headers.map ?? <String, dynamic>{},
        ),
        responseBody: responseBody,
        error: error?.message ?? error?.toString(),
        stackTrace: stackTrace?.toString(),
        violations: violations,
      );
    });
  }
}
