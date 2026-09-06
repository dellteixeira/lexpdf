import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf_acroform/pdf_acroform.dart';
import 'package:pdf_acroform/pdf_acroform_viewer.dart';

import '../core/documents/document_provider.dart';
import '../core/storage/local_pdf_form_store.dart';

class PdfFormsScreen extends StatefulWidget {
  const PdfFormsScreen({
    required this.document,
    required this.store,
    super.key,
  });

  final DocumentRef document;
  final LocalPdfFormStore store;

  @override
  State<PdfFormsScreen> createState() => _PdfFormsScreenState();
}

class _PdfFormsScreenState extends State<PdfFormsScreen> {
  List<PdfFormField>? _fields;
  Map<String, dynamic> _formData = const {};
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final path = widget.document.localPath;
    if (path == null || path.isEmpty) {
      setState(() => _error = StateError('O PDF precisa estar disponível offline.'));
      return;
    }
    try {
      final parser = await AcroFormParser.fromFile(path);
      final fields = await parser.extractFields();
      final defaults = fields.extractFormData();
      final stored = await widget.store.load(widget.document.id);
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _formData = <String, dynamic>{...defaults, ...stored};
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _fieldChanged(String name, dynamic value) async {
    setState(() {
      _formData = <String, dynamic>{..._formData, name: value};
      _saving = true;
    });
    try {
      await widget.store.setValue(
        documentId: widget.document.id,
        fieldName: name,
        value: value,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final fields = _fields;
    if (fields == null) return;
    await widget.store.clear(widget.document.id);
    if (!mounted) return;
    setState(() => _formData = fields.extractFormData());
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Formulários PDF'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Restaurar valores originais',
            onPressed: _fields == null ? null : _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Não foi possível carregar o formulário: $_error'))
          : _fields == null
              ? const Center(child: CircularProgressIndicator())
              : _fields!.isEmpty
                  ? const Center(
                      child: Text('Este PDF não contém campos AcroForm detectáveis.'),
                    )
                  : PdfFormViewer(
                      pdfPath: path!,
                      fields: _fields!,
                      formData: _formData,
                      style: PdfFormStyle.fromTheme(Theme.of(context)),
                      onFieldChanged: _fieldChanged,
                    ),
    );
  }
}
