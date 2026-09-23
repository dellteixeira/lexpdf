import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unified workspace uses bounded adaptive render cache on Android and Windows', () {
    final workspace = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final policy =
        File('lib/src/core/pdf/huge_pdf_policy.dart').readAsStringSync();

    expect(workspace, contains('int _renderCacheBudget(BuildContext context)'));
    expect(workspace, contains('HugePdfPolicy.viewerImageCacheBytesFor('));
    expect(workspace, contains('isWindows: _windows'));
    expect(workspace, contains('pageCount: _document?.pages.length ?? 0'));
    expect(workspace, contains('MediaQuery.devicePixelRatioOf(context)'));
    expect(workspace, contains('androidRecoveryLevel:'));
    expect(
      workspace,
      contains('maxImageBytesCachedOnMemory:'),
    );
    expect(workspace, contains('_renderCacheBudget(context)'));
    expect(
      workspace,
      isNot(contains('? 100 * 1024 * 1024\n                                : HugePdfPolicy.viewerImageCacheBytes')),
    );

    expect(policy, contains('required double viewportWidth'));
    expect(policy, contains('required double viewportHeight'));
    expect(policy, contains('required double devicePixelRatio'));
    expect(policy, contains('devicePixelRatio.clamp(1.0, 3.0)'));
    expect(policy, contains('>= 3000'));
    expect(policy, contains('>= 1000'));
    expect(policy, contains('int androidRecoveryLevel = 0'));
    expect(policy, contains('_mobileEmergencyCacheMaxBytes'));
  });
}
