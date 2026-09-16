import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner enforces single instance and forwards document paths', () {
    final main = File('windows/runner/main.cpp').readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(main, contains('LexPDF.SingleInstance.v1'));
    expect(main, contains('WM_COPYDATA'));
    expect(main, contains('SetForegroundWindow'));
    expect(main, contains('ForwardToExistingInstance'));
    expect(window, contains('DragAcceptFiles'));
    expect(window, contains('WM_DROPFILES'));
    expect(window, contains('recursive_directory_iterator'));
    expect(window, contains('lexpdf/native_pdf_open'));
    expect(window, contains('openPdfPath'));
  });

  test('Windows installer registers PDF integration without forcing UserChoice', () {
    final installer = File('windows/installer/LexPDF.iss').readAsStringSync();

    expect(installer, contains('ChangesAssociations=yes'));
    expect(installer, contains('LexPDF.Document'));
    expect(installer, contains('.pdf\\OpenWithProgids'));
    expect(installer, contains('Abrir com LexPDF'));
    expect(installer, contains('"%1"'));
    expect(installer, isNot(contains('UserChoice')));
  });

  test('Dart native PDF intake listens on Windows', () {
    final service = File(
      'lib/src/core/documents/native_pdf_open_service.dart',
    ).readAsStringSync();
    expect(service, contains('Platform.isWindows'));
    expect(service, contains("MethodChannel('lexpdf/native_pdf_open')"));
  });
}
