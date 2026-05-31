enum ApiLogStatus { pending, success, error }

class ApiLogEntry {
  ApiLogEntry({
    required this.id,
    required this.method,
    required this.uri,
    required this.path,
    required this.startedAt,
    this.completedAt,
    this.statusCode,
    this.durationMs,
    this.status = ApiLogStatus.pending,
    this.requestHeaders = const <String, Object?>{},
    this.requestBody,
    this.responseHeaders = const <String, Object?>{},
    this.responseBody,
    this.error,
    this.stackTrace,
    this.violations = const <ContractViolation>[],
  });

  final String id;
  final String method;
  final String uri;
  final String path;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? statusCode;
  final int? durationMs;
  final ApiLogStatus status;
  final Map<String, Object?> requestHeaders;
  final Object? requestBody;
  final Map<String, Object?> responseHeaders;
  final Object? responseBody;
  final String? error;
  final String? stackTrace;
  final List<ContractViolation> violations;

  bool get hasError => status == ApiLogStatus.error || error != null;
  bool get hasViolation => violations.isNotEmpty;

  ApiLogEntry copyWith({
    DateTime? completedAt,
    int? statusCode,
    int? durationMs,
    ApiLogStatus? status,
    Map<String, Object?>? responseHeaders,
    Object? responseBody,
    String? error,
    String? stackTrace,
    List<ContractViolation>? violations,
  }) {
    return ApiLogEntry(
      id: id,
      method: method,
      uri: uri,
      path: path,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
      status: status ?? this.status,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      violations: violations ?? this.violations,
    );
  }

  Map<String, Object?> toSummaryJson() {
    return <String, Object?>{
      'id': id,
      'method': method,
      'uri': uri,
      'path': path,
      'startedAt': startedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'statusCode': statusCode,
      'durationMs': durationMs,
      'status': status.name,
      'hasError': hasError,
      'hasViolation': hasViolation,
      'violationCount': violations.length,
      'error': error,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...toSummaryJson(),
      'requestHeaders': requestHeaders,
      'requestBody': requestBody,
      'responseHeaders': responseHeaders,
      'responseBody': responseBody,
      'stackTrace': stackTrace,
      'violations': violations.map((item) => item.toJson()).toList(),
    };
  }
}

class ContractViolation {
  const ContractViolation({
    required this.field,
    required this.expected,
    required this.actual,
    required this.message,
    this.severity = 'warning',
  });

  final String field;
  final String expected;
  final String actual;
  final String message;
  final String severity;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'field': field,
      'expected': expected,
      'actual': actual,
      'message': message,
      'severity': severity,
    };
  }
}
