import 'package:api_observer_flutter/api_observer_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates required fields and string length', () {
    final validator = ApiContractValidator(
      const [
        ApiContractRule(
          method: 'GET',
          pathPattern: '/users/1',
          fields: [
            FieldRule('id', type: FieldType.integer, required: true, nullable: false),
            FieldRule('name', type: FieldType.string, required: true, maxLength: 3),
            FieldRule('email', type: FieldType.string, required: true),
          ],
        ),
      ],
    );

    final violations = validator.validate(
      method: 'GET',
      path: '/users/1',
      body: <String, Object?>{'id': '1', 'name': 'Alice'},
    );

    expect(violations.map((item) => item.field), containsAll(<String>['id', 'name', 'email']));
  });
}
