import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RC1 evidence bootstrap auto-chains successful distribution runs', () {
    final workflow = File(
      '../../.github/workflows/rc1-evidence-bootstrap.yml',
    ).readAsStringSync();

    expect(workflow, contains('name: RC1 Automated Evidence Bootstrap'));
    expect(workflow, contains('workflow_run:'));
    expect(workflow, contains('- Release Candidate Distribution'));
    expect(workflow, contains('- completed'));
    expect(
      workflow,
      contains("github.event.workflow_run.conclusion == 'success'"),
    );
    expect(
      workflow,
      contains('github.event.workflow_run.id || inputs.distribution_run_id'),
    );
    expect(
      workflow,
      contains('github.event.workflow_run.head_sha || inputs.candidate_sha'),
    );
  });

  test('RC1 evidence bootstrap keeps manual fallback and exact SHA binding', () {
    final workflow = File(
      '../../.github/workflows/rc1-evidence-bootstrap.yml',
    ).readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('distribution_run_id:'));
    expect(workflow, contains('candidate_sha:'));
    expect(workflow, contains("test \"\$actual_sha\" = \"\$CANDIDATE_SHA\""));
    expect(workflow, contains("test \"\$conclusion\" = 'success'"));
    expect(
      workflow,
      contains("test \"\$workflow_name\" = 'Release Candidate Distribution'"),
    );
  });

  test('RC1 evidence bootstrap downloads resolved run artifacts and verifies hashes', () {
    final workflow = File(
      '../../.github/workflows/rc1-evidence-bootstrap.yml',
    ).readAsStringSync();

    expect(workflow, contains('actions/download-artifact@v4'));
    expect(workflow, contains(r'run-id: ${{ env.RUN_ID }}'));
    expect(workflow, contains(r'ref: ${{ env.CANDIDATE_SHA }}'));
    expect(workflow, contains('SHA256SUMS-Android.txt'));
    expect(workflow, contains('SHA256SUMS-Windows.txt'));
    expect(workflow, contains('SHA256SUMS-macOS.txt'));
    expect(workflow, contains('verify_named_hash'));
    expect(workflow, contains('app-release.apk'));
    expect(workflow, contains('app-release.aab'));
    expect(workflow, contains("find rc-artifacts -type f -iname '*.exe'"));
    expect(workflow, contains("find rc-artifacts -type f -name '*.dmg'"));
  });

  test('automated evidence explicitly does not replace real runtime evidence', () {
    final workflow = File(
      '../../.github/workflows/rc1-evidence-bootstrap.yml',
    ).readAsStringSync();

    expect(workflow, contains('RC1_AUTOMATED_EVIDENCE.md'));
    expect(workflow, contains('Recomputed hashes match'));
    expect(workflow, contains('does **not** replace certificate identity capture'));
    expect(workflow, contains('real-device/runtime validation'));
    expect(workflow, contains('first usable rendered-page timing'));
    expect(workflow, contains('memory measurements'));
    expect(workflow, contains('Automated-Evidence'));
  });
}
