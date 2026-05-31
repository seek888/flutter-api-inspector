class ApiLogRedactor {
  ApiLogRedactor({
    Set<String>? sensitiveKeys,
    this.mask = '<redacted>',
    this.maxBodyCharacters = 120000,
  }) : sensitiveKeys = sensitiveKeys ?? _defaultSensitiveKeys;

  static const Set<String> _defaultSensitiveKeys = <String>{
    'authorization',
    'cookie',
    'set-cookie',
    'token',
    'access_token',
    'refresh_token',
    'password',
    'pwd',
    'secret',
    'idcard',
    'id_card',
    'phone',
    'mobile',
  };

  final Set<String> sensitiveKeys;
  final String mask;
  final int maxBodyCharacters;

  Object? redact(Object? value) {
    return _redactValue(value, null);
  }

  Map<String, Object?> redactHeaders(Map<String, dynamic> headers) {
    return headers.map((key, value) {
      return MapEntry<String, Object?>(
        key,
        _isSensitive(key) ? mask : redact(value),
      );
    });
  }

  Object? _redactValue(Object? value, String? key) {
    if (key != null && _isSensitive(key)) {
      return mask;
    }
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is Uri) {
      return value.toString();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is String) {
      return _truncate(value);
    }
    if (value is Map) {
      return value.map((mapKey, mapValue) {
        final stringKey = mapKey.toString();
        return MapEntry<String, Object?>(
          stringKey,
          _redactValue(mapValue, stringKey),
        );
      });
    }
    if (value is Iterable) {
      return value
          .map((item) => _redactValue(item, null))
          .toList(growable: false);
    }
    return _truncate(value.toString());
  }

  String _truncate(String value) {
    if (value.length <= maxBodyCharacters) {
      return value;
    }
    return '${value.substring(0, maxBodyCharacters)}...<truncated>';
  }

  bool _isSensitive(String key) {
    final normalized = key.toLowerCase().replaceAll('-', '_');
    return sensitiveKeys.contains(normalized) ||
        sensitiveKeys.contains(key.toLowerCase());
  }
}
