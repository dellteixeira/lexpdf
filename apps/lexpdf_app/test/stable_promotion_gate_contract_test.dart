import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable promotion stays manual and requires exact RC evidence', () {
    final workflow = File(
      '../../.github/workflows/stable-promotion.yml',
    ).readAsStringSync();

    expect(workflow, contains('name: Stable Promotion Gate'));
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('accepted_rc_sha:'));
    expect(workflow, contains('release_tag:'));
    expect(workflow, contains('fetch-depth: 0'));
    expect(workflow, contains('docs/RC1_ACCEPTANCE.md'));
    expect(workflow, contains("grep -q '^- \\[ \\]' \"\$manifest\""));
    expect(workflow, contains('Accepted RC SHA is not recorded'));
    expect(workflow, contains('git merge-base --is-ancestor'));
  });

  test('stable promotion rejects RC versions and non-v1.0.0 tags', () {
    final workflow = File(
      '../../.github/workflows/stable-promotion.yml',
    ).readAsStringSync();

    expect(workflow, contains(r'^1\.0\.0\+[1-9][0-9]*$'));
    expect(workflow, contains('RC prerelease suffix is not allowed'));
    expect(workflow, contains("[[ \"\$RELEASE_TAG\" != 'v1.0.0' ]]"));
    expect(workflow, contains('accepted_rc_sha must be an exact 40-character'));
  });

  test('stable promotion reruns critical acceptance coverage', () {
    final workflow = File(
      '../../.github/workflows/stable-promotion.yml',
    ).readAsStringSync();

    for (final testFile in <String>[
      'very_large_pdf_acceptance_test.dart',
      'huge_pdf_persistence_test.dart',
      'platform_feature_parity_contract_test.dart',
      'native_pdf_reopen_lifecycle_contract_test.dart',
      'reading_progress_session_preservation_test.dart',
      'rc1_acceptance_manifest_contract_test.dart',
    ]) {
      expect(workflow, contains(testFile));
    }

    expect(
      workflow,
      contains('This gate does not create the GitHub Release or regenerate signed artifacts.'),
    );
  });
}
