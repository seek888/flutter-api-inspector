import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'contract.dart';
import 'models.dart';
import 'redactor.dart';
import 'store.dart';

class ApiObserver {
  ApiObserver._();

  static final ApiObserver instance = ApiObserver._();

  final ApiLogStore store = ApiLogStore();
  ApiLogRedactor redactor = ApiLogRedactor();
  ApiContractValidator? validator;
  bool _registered = false;
  int _sequence = 0;

  void configure({ApiLogRedactor? redactor, ApiContractValidator? validator}) {
    if (redactor != null) {
      this.redactor = redactor;
    }
    this.validator = validator;
  }

  void registerVmServiceExtensions() {
    if (kReleaseMode || _registered) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    _registered = true;
    _register('ping', _ping);
    _register('listRequests', _listRequests);
    _register('getRequest', _getRequest);
    _register('listViolations', _listViolations);
    _register('clear', _clear);
  }

  String nextId() {
    _sequence += 1;
    return 'req_${DateTime.now().microsecondsSinceEpoch}_$_sequence';
  }

  void add(ApiLogEntry entry) {
    store.add(entry);
  }

  void update(String id, ApiLogEntry Function(ApiLogEntry entry) updater) {
    store.update(id, updater);
  }

  Future<Map<String, dynamic>> _ping(Map<String, String> parameters) async {
    return <String, dynamic>{
      'ok': true,
      'name': 'api_observer_flutter',
      'version': '0.0.1',
      'time': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _listRequests(
    Map<String, String> parameters,
  ) async {
    final limit = int.tryParse(parameters['limit'] ?? '') ?? 100;
    final offset = int.tryParse(parameters['offset'] ?? '') ?? 0;
    final query = parameters['query'];
    final onlyErrors = parameters['onlyErrors'] == 'true';
    final onlyViolations = parameters['onlyViolations'] == 'true';
    return <String, dynamic>{
      'requests': store
          .list(
            query: query,
            offset: offset,
            limit: limit,
            onlyErrors: onlyErrors,
            onlyViolations: onlyViolations,
          )
          .map((entry) => entry.toSummaryJson())
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _getRequest(
    Map<String, String> parameters,
  ) async {
    final id = parameters['id'];
    final entry = id == null ? null : store.getById(id);
    return <String, dynamic>{'request': entry?.toJson()};
  }

  Future<Map<String, dynamic>> _listViolations(
    Map<String, String> parameters,
  ) async {
    return <String, dynamic>{
      'requests': store.violations.map((entry) => entry.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> _clear(Map<String, String> parameters) async {
    store.clear();
    return <String, dynamic>{'ok': true};
  }

  void _register(
    String name,
    FutureOr<Map<String, dynamic>> Function(Map<String, String> parameters)
    callback,
  ) {
    registerExtension('ext.api_observer.$name', (method, parameters) async {
      try {
        final result = await callback(parameters);
        return ServiceExtensionResponse.result(jsonEncode(result));
      } catch (error, stackTrace) {
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          jsonEncode(<String, Object?>{
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          }),
        );
      }
    });
  }
}
