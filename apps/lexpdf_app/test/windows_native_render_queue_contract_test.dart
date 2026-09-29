import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows native PDF rendering coalesces requests on one worker per surface', () {
    final native = File(
      'windows/runner/windows_native_pdf_surface.cpp',
    ).readAsStringSync();

    expect(native, contains('std::condition_variable render_cv_'));
    expect(native, contains('std::optional<PendingRender> pending_render_'));
    expect(native, contains('render_worker_ = std::thread([this]() { RenderLoop(); })'));
    expect(native, contains('pending_render_ ='));
    expect(native, contains('render_worker_.join()'));
    expect(native, isNot(contains('}).detach();')));
  });

  test('Windows native PDF cache key includes file version metadata', () {
    final native = File(
      'windows/runner/windows_native_pdf_surface.cpp',
    ).readAsStringSync();

    expect(native, contains('FileVersionKey'));
    expect(native, contains('std::filesystem::file_size'));
    expect(native, contains('std::filesystem::last_write_time'));
    expect(native, contains('path + "|" + FileVersionKey(path)'));
  });
}
