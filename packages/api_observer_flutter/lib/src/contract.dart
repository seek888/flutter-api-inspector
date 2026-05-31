import 'models.dart';

class ApiContractRule {
  const ApiContractRule({
    required this.method,
    required this.pathPattern,
    required this.fields,
  });

  final String method;
  final Pattern pathPattern;
  final List<FieldRule> fields;

  bool matches(String requestMethod, String requestPath) {
    if (method.toUpperCase() != requestMethod.toUpperCase()) {
      return false;
    }
    final pattern = pathPattern;
    if (pattern is String) {
      return pattern == requestPath;
    }
    return pattern.allMatches(requestPath).isNotEmpty;
  }
}

enum FieldType { any, string, integer, number, boolean, object, array }

class FieldRule {
  const FieldRule(
    this.path, {
    this.type = FieldType.any,
    this.required = false,
    this.nullable = true,
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.pattern,
    this.oneOf,
    this.url = false,
    this.date = false,
  });

  final String path;
  final FieldType type;
  final bool required;
  final bool nullable;
  final int? minLength;
  final int? maxLength;
  final num? min;
  final num? max;
  final RegExp? pattern;
  final List<Object?>? oneOf;
  final bool url;
  final bool date;
}

class ApiContractValidator {
  ApiContractValidator(this.rules);

  final List<ApiContractRule> rules;

  List<ContractViolation> validate({
    required String method,
    required String path,
    required Object? body,
  }) {
    final matchingRules = rules.where((rule) => rule.matches(method, path));
    final violations = <ContractViolation>[];
    for (final rule in matchingRules) {
      for (final field in rule.fields) {
        violations.addAll(_validateField(field, body));
      }
    }
    return violations;
  }

  List<ContractViolation> _validateField(FieldRule rule, Object? body) {
    final result = _readPath(body, rule.path);
    final violations = <ContractViolation>[];
    if (!result.exists) {
      if (rule.required) {
        violations.add(
          _violation(rule, 'present value', 'missing', 'Field is required.'),
        );
      }
      return violations;
    }
    final value = result.value;
    if (value == null) {
      if (!rule.nullable) {
        violations.add(
          _violation(rule, 'non-null value', 'null', 'Field cannot be null.'),
        );
      }
      return violations;
    }
    if (!_matchesType(value, rule.type)) {
      violations.add(
        _violation(
          rule,
          rule.type.name,
          _typeOf(value),
          'Field type does not match.',
        ),
      );
      return violations;
    }
    if (value is String) {
      if (rule.minLength != null && value.length < rule.minLength!) {
        violations.add(
          _violation(
            rule,
            'length >= ${rule.minLength}',
            'length ${value.length}',
            'String is too short.',
          ),
        );
      }
      if (rule.maxLength != null && value.length > rule.maxLength!) {
        violations.add(
          _violation(
            rule,
            'length <= ${rule.maxLength}',
            'length ${value.length}',
            'String is too long.',
          ),
        );
      }
      if (rule.pattern != null && !rule.pattern!.hasMatch(value)) {
        violations.add(
          _violation(
            rule,
            'pattern ${rule.pattern!.pattern}',
            value,
            'String does not match pattern.',
          ),
        );
      }
      if (rule.url && Uri.tryParse(value)?.hasAbsolutePath != true) {
        violations.add(
          _violation(rule, 'absolute URL', value, 'String is not a valid URL.'),
        );
      }
      if (rule.date && DateTime.tryParse(value) == null) {
        violations.add(
          _violation(
            rule,
            'date/datetime string',
            value,
            'String is not a valid date.',
          ),
        );
      }
    }
    if (value is num) {
      if (rule.min != null && value < rule.min!) {
        violations.add(
          _violation(rule, '>= ${rule.min}', value, 'Number is too small.'),
        );
      }
      if (rule.max != null && value > rule.max!) {
        violations.add(
          _violation(rule, '<= ${rule.max}', value, 'Number is too large.'),
        );
      }
    }
    if (rule.oneOf != null && !rule.oneOf!.contains(value)) {
      violations.add(
        _violation(
          rule,
          'one of ${rule.oneOf}',
          value,
          'Value is not in allowed set.',
        ),
      );
    }
    return violations;
  }

  bool _matchesType(Object value, FieldType type) {
    return switch (type) {
      FieldType.any => true,
      FieldType.string => value is String,
      FieldType.integer => value is int,
      FieldType.number => value is num,
      FieldType.boolean => value is bool,
      FieldType.object => value is Map,
      FieldType.array => value is List,
    };
  }

  _PathResult _readPath(Object? body, String path) {
    Object? current = body;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else if (current is List && int.tryParse(segment) != null) {
        final index = int.parse(segment);
        if (index < 0 || index >= current.length) {
          return const _PathResult(false, null);
        }
        current = current[index];
      } else {
        return const _PathResult(false, null);
      }
    }
    return _PathResult(true, current);
  }

  ContractViolation _violation(
    FieldRule rule,
    Object? expected,
    Object? actual,
    String message,
  ) {
    return ContractViolation(
      field: rule.path,
      expected: expected.toString(),
      actual: actual.toString(),
      message: message,
    );
  }

  String _typeOf(Object value) {
    if (value is String) {
      return 'string';
    }
    if (value is int) {
      return 'integer';
    }
    if (value is num) {
      return 'number';
    }
    if (value is bool) {
      return 'boolean';
    }
    if (value is List) {
      return 'array';
    }
    if (value is Map) {
      return 'object';
    }
    return value.runtimeType.toString();
  }
}

class _PathResult {
  const _PathResult(this.exists, this.value);

  final bool exists;
  final Object? value;
}
