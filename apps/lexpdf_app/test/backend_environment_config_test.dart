import 'package:flutter_test/flutter_test.dart';
import 'package:lexpdf_app/src/core/backend/backend_config.dart';

void main() {
  test('default compile-time environment is non-production', () {
    expect(BackendConfig.environment, 'development');
    expect(BackendConfig.fromEnvironment.hasSupabase, isFalse);
    expect(BackendConfig.fromEnvironment.hasCloudGateway, isFalse);
    expect(BackendConfig.fromEnvironment.hasAiGateway, isFalse);
  });
}
