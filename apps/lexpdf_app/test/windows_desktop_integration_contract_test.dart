import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner forwards second-instance PDFs into the first window', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(main, contains('CreateMutexW'));
    expect(main, contains('ERROR_ALREADY_EXISTS'));
    expect(main, contains('FindWindowW'));
    expect(main, contains('WM_COPYDATA'));
    expect(main, contains('SetForegroundWindow'));
    expect(window, contains('WM_COPYDATA'));
    expect(window, contains('openPdfPaths'));
    expect(window, contains('lexpdf/native_pdf_open'));
  });

  test('Windows runner accepts Explorer PDF and folder drops', () {
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();

    expect(window, contains('DragAcceptFiles'));
    expect(window, contains('WM_DROPFILES'));
    expect(window, contains('DragQueryFileW'));
    expect(window, contains('recursive_directory_iterator'));
    expect(window, contains('kMaxNativePdfBatch = 10'));
    expect(cmake, contains('shell32.lib'));
  });

  test('Dart native-open bridge supports Windows batches and real PDF tabs', () {
    final service = File(
      'lib/src/core/documents/native_pdf_open_service.dart',
    ).readAsStringSync();
    final app = File('lib/src/lexpdf_app.dart').readAsStringSync();

    expect(service, contains('Platform.isWindows'));
    expect(service, contains("call.method == 'openPdfPaths'"));
    expect(service, contains('onOpenMany'));
    expect(app, contains('_openNativePdfBatch'));
    expect(app, contains('LocalPdfWorkspaceSessionStore'));
    expect(app, contains('PdfWorkspaceTabState'));
    expect(app, contains('while (merged.length > 10)'));
  });

  test('Windows installer registers shortcuts and a non-invasive PDF handler', () {
    final installer = File('windows/installer/lexpdf.iss').readAsStringSync();

    expect(installer, contains('PrivilegesRequired=lowest'));
    expect(installer, contains('ChangesAssociations=yes'));
    expect(installer, contains('OpenWithProgids'));
    expect(installer, contains('LexPDF.PDF'));
    expect(installer, contains('Software\\RegisteredApplications'));
    expect(installer, contains('{userdesktop}\\LexPDF'));
    expect(installer, contains('LexPDF-Setup'));
    expect(
      installer,
      isNot(
        contains(
          'Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\.pdf\\UserChoice',
        ),
      ),
    );
  });
}
