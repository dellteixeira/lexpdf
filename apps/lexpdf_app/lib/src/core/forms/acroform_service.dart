import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_reader/dart_pdf_reader.dart';

enum LexPdfFormFieldType { text, button, choice, signature, unknown }

class LexPdfFormField {
  const LexPdfFormField({
    required this.name,
    required this.type,
    required this.pageIndex,
    this.defaultValue,
    this.isMultiline = false,
    this.isReadOnly = false,
    this.maxLength,
    this.options = const [],
  });

  final String name;
  final LexPdfFormFieldType type;
  final int pageIndex;
  final String? defaultValue;
  final bool isMultiline;
  final bool isReadOnly;
  final int? maxLength;
  final List<String> options;

  dynamic get initialValue {
    final value = defaultValue;
    if (value == null || value.isEmpty) return null;
    if (type == LexPdfFormFieldType.button) {
      final normalized = value.toLowerCase();
      return normalized != 'off' && normalized != 'no' && normalized != '0';
    }
    return value;
  }
}

extension LexPdfFormFields on List<LexPdfFormField> {
  Map<String, dynamic> initialData() {
    final result = <String, dynamic>{};
    for (final field in this) {
      final value = field.initialValue;
      if (value != null) result[field.name] = value;
    }
    return result;
  }
}

/// Pure-Dart AcroForm metadata reader used by LexPDF.
///
/// It intentionally does not depend on a PDF viewer package. Rendering stays
/// with pdfrx while field metadata is read directly from the PDF object graph,
/// which keeps the forms feature portable across Android, Windows and macOS.
class LexPdfAcroFormService {
  const LexPdfAcroFormService();

  Future<List<LexPdfFormField>> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return readBytes(bytes);
  }

  Future<List<LexPdfFormField>> readBytes(Uint8List bytes) async {
    final document = await PDFParser(ByteStream(bytes)).parse();
    final result = <LexPdfFormField>[];
    final catalog = await document.catalog;
    final acroRef = catalog.dictionary[const PDFName('AcroForm')];
    if (acroRef == null) return result;
    final acro = await _resolve(document, acroRef);
    if (acro is! PDFDictionary) return result;
    final fieldsRef = acro[const PDFName('Fields')];
    if (fieldsRef == null) return result;
    final fields = await _resolve(document, fieldsRef);
    if (fields is! PDFArray) return result;

    for (final field in fields) {
      await _readField(
        document: document,
        source: field,
        target: result,
        parentName: '',
        inheritedType: null,
        inheritedFlags: 0,
      );
    }
    return result;
  }

  Future<void> _readField({
    required PDFDocument document,
    required PDFObject source,
    required List<LexPdfFormField> target,
    required String parentName,
    required LexPdfFormFieldType? inheritedType,
    required int inheritedFlags,
  }) async {
    final resolved = await _resolve(document, source);
    if (resolved is! PDFDictionary) return;

    final localName = await _stringValue(document, resolved[const PDFName('T')]);
    final name = parentName.isEmpty
        ? (localName ?? '')
        : localName == null || localName.isEmpty
            ? parentName
            : '$parentName.$localName';
    final type = await _fieldType(document, resolved) ??
        inheritedType ??
        LexPdfFormFieldType.unknown;
    final flags = await _intValue(document, resolved[const PDFName('Ff')]) ??
        inheritedFlags;

    final kidsRef = resolved[const PDFName('Kids')];
    if (kidsRef != null) {
      final kids = await _resolve(document, kidsRef);
      if (kids is PDFArray) {
        for (final kid in kids) {
          await _readField(
            document: document,
            source: kid,
            target: target,
            parentName: name,
            inheritedType: type,
            inheritedFlags: flags,
          );
        }
      }
    }

    if (name.isEmpty || resolved[const PDFName('Rect')] == null) return;
    final value = await _stringValue(document, resolved[const PDFName('V')]);
    final maxLength = await _intValue(document, resolved[const PDFName('MaxLen')]);
    final options = type == LexPdfFormFieldType.choice
        ? await _choiceOptions(document, resolved)
        : const <String>[];
    final pageIndex = await _pageIndex(document, resolved);

    // Widget kids and parent fields can both describe the same logical field.
    if (target.any((item) => item.name == name && item.pageIndex == pageIndex)) {
      return;
    }
    target.add(
      LexPdfFormField(
        name: name,
        type: type,
        pageIndex: pageIndex,
        defaultValue: value,
        isMultiline: type == LexPdfFormFieldType.text && (flags & 4096) != 0,
        isReadOnly: (flags & 1) != 0,
        maxLength: maxLength,
        options: options,
      ),
    );
  }

  Future<LexPdfFormFieldType?> _fieldType(
    PDFDocument document,
    PDFDictionary field,
  ) async {
    final ref = field[const PDFName('FT')];
    if (ref == null) return null;
    final value = await _resolve(document, ref);
    if (value is! PDFName) return null;
    return switch (value.value) {
      'Tx' => LexPdfFormFieldType.text,
      'Btn' => LexPdfFormFieldType.button,
      'Ch' => LexPdfFormFieldType.choice,
      'Sig' => LexPdfFormFieldType.signature,
      _ => LexPdfFormFieldType.unknown,
    };
  }

  Future<List<String>> _choiceOptions(
    PDFDocument document,
    PDFDictionary field,
  ) async {
    final ref = field[const PDFName('Opt')];
    if (ref == null) return const [];
    final value = await _resolve(document, ref);
    if (value is! PDFArray) return const [];
    final result = <String>[];
    for (final item in value) {
      final resolved = await _resolve(document, item);
      if (resolved is PDFStringLike) {
        result.add(resolved.asString());
      } else if (resolved is PDFArray && resolved.isNotEmpty) {
        final display = await _resolve(
          document,
          resolved.length > 1 ? resolved[1] : resolved[0],
        );
        if (display is PDFStringLike) result.add(display.asString());
      }
    }
    return result;
  }

  Future<int> _pageIndex(PDFDocument document, PDFDictionary field) async {
    final pageRef = field[const PDFName('P')];
    if (pageRef == null) return 0;
    final pageObject = await _resolve(document, pageRef);
    if (pageObject is! PDFDictionary) return 0;
    final catalog = await document.catalog;
    final pages = await catalog.getPages();
    for (var i = 0; i < pages.pageCount; i++) {
      final page = pages.getPageAtIndex(i);
      if (identical(page.dictionary, pageObject) || page.dictionary == pageObject) {
        return i;
      }
    }
    return 0;
  }

  Future<String?> _stringValue(PDFDocument document, PDFObject? source) async {
    if (source == null) return null;
    final value = await _resolve(document, source);
    if (value is PDFStringLike) return value.asString();
    if (value is PDFName) return value.value;
    return null;
  }

  Future<int?> _intValue(PDFDocument document, PDFObject? source) async {
    if (source == null) return null;
    final value = await _resolve(document, source);
    return value is PDFNumber ? value.toInt() : null;
  }

  Future<PDFObject> _resolve(PDFDocument document, PDFObject source) async {
    return await document.resolve(source) ?? source;
  }
}
