import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android PDF viewer arms crash guard before mounting PDFium', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ');

    expect(source, contains('PdfOpenCrashGuard _openCrashGuard'));
    expect(source, contains('_armAndroidOpenCrashGuard'));
    expect(source, contains('_openCrashGuard.begin(widget.document.id)'));
    expect(source, contains('if (_android && !_openGuardReady)'));
    expect(
      normalized,
      contains('androidRecoveryLevel: _android ? _androidRecoveryLevel : 0'),
    );
  });

  test('recovery levels reduce render pressure and delay optional work', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();
    final policy =
        File('lib/src/core/pdf/huge_pdf_policy.dart').readAsStringSync();

    expect(source, contains('androidOnePassThresholdForRecovery'));
    expect(source, contains('androidMaxRenderLongEdgeForRecovery'));
    expect(source, contains('androidCacheExtentForRecovery'));
    expect(source, contains('androidStableOpenWindow'));
    expect(source, contains('_completeStableAndroidOpen'));
    expect(source, contains('androidRecoverySecondaryWorkDelay'));

    expect(policy, contains('_mobileRecoveryCacheMaxBytes = 12 * 1024 * 1024'));
    expect(policy, contains('_mobileEmergencyCacheMaxBytes = 8 * 1024 * 1024'));
    expect(policy, contains('androidRecoveryOnePassRenderingSizeThreshold = 700'));
    expect(policy, contains('androidEmergencyOnePassRenderingSizeThreshold = 512'));
    expect(policy, contains('androidRecoveryMaxRenderLongEdge = 1600'));
    expect(policy, contains('androidEmergencyMaxRenderLongEdge = 1200'));
    expect(policy, contains('androidEmergencyCacheExtent = 0.0'));
  });

  test('successful stable opening clears guard while native crashes leave it behind', () {
    final source = File(
      'lib/src/screens/pdf_workspace_stylus_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_openCrashGuard.markStable(widget.document.id)'));
    expect(source, contains('_stableOpenTimer = Timer('));
    expect(source, contains('HugePdfPolicy.androidStableOpenWindow'));
    expect(source, contains('if (_androidRecoveryLevel > 0)'));
    expect(source, contains('widget.onViewerDocumentChanged?.call(document)'));
  });
}
