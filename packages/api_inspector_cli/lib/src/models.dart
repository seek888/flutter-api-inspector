class InspectorRequestSummary {
  const InspectorRequestSummary({
    required this.id,
    required this.method,
    required this.uri,
    required this.path,
    required this.startedAt,
    this.statusCode,
    this.durationMs,
    this.status,
    this.hasError = false,
    this.hasViolation = false,
    this.violationCount = 0,
    this.error,
  });

  final String id;
  final String method;
  final String uri;
  final String path;
  final DateTime startedAt;
  final int? statusCode;
  final int? durationMs;
  final String? status;
  final bool hasError;
  final bool hasViolation;
  final int violationCount;
  final String? error;

  factory InspectorRequestSummary.fromJson(Map<String, Object?> json) {
    return InspectorRequestSummary(
      id: json['id'] as String,
      method: json['method'] as String? ?? '',
      uri: json['uri'] as String? ?? '',
      path: json['path'] as String? ?? '',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      statusCode: json['statusCode'] as int?,
      durationMs: json['durationMs'] as int?,
      status: json['status'] as String?,
      hasError: json['hasError'] as bool? ?? false,
      hasViolation: json['hasViolation'] as bool? ?? false,
      violationCount: json['violationCount'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'method': method,
      'uri': uri,
      'path': path,
      'startedAt': startedAt.toIso8601String(),
      'statusCode': statusCode,
      'durationMs': durationMs,
      'status': status,
      'hasError': hasError,
      'hasViolation': hasViolation,
      'violationCount': violationCount,
      'error': error,
    };
  }
}
