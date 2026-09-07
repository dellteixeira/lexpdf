import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/documents/document_provider.dart';
import '../core/forms/acroform_service.dart';
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
  final LexPdfAcroFormService _acroForms = const LexPdfAcroFormService();
  List<LexPdfFormField>? _fields;
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
      final fields = await _acroForms.readFile(path);
      final defaults = fields.initialData();
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
    setState(() => _formData = fields.initialData());
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.document.localPath;
    final fields = _fields;
    return Scaffold(
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
            onPressed: fields == null ? null : _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Não foi possível carregar o formulário: $_error'))
          : fields == null
              ? const Center(child: CircularProgressIndicator())
              : fields.isEmpty
                  ? const Center(
                      child: Text('Este PDF não contém campos AcroForm detectáveis.'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 900;
                        final viewer = PdfViewer.file(
                          path!,
                          params: const PdfViewerParams(
                            textSelectionParams:
                                PdfTextSelectionParams(enabled: false),
                          ),
                        );
                        final editor = _FormFieldPanel(
                          fields: fields,
                          values: _formData,
                          onChanged: _fieldChanged,
                        );
                        if (compact) {
                          return Column(
                            children: [
                              Expanded(flex: 3, child: viewer),
                              const Divider(height: 1),
                              Expanded(flex: 2, child: editor),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(flex: 3, child: viewer),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 380, child: editor),
                          ],
                        );
                      },
                    ),
    );
  }
}

class _FormFieldPanel extends StatelessWidget {
  const _FormFieldPanel({
    required this.fields,
    required this.values,
    required this.onChanged,
  });

  final List<LexPdfFormField> fields;
  final Map<String, dynamic> values;
  final Future<void> Function(String name, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: fields.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Text(
            'Campos detectados no PDF. Os valores editados são salvos localmente e permanecem disponíveis offline.',
          );
        }
        final field = fields[index - 1];
        return _FormFieldEditor(
          key: ValueKey('${field.pageIndex}:${field.name}'),
          field: field,
          value: values[field.name] ?? field.initialValue,
          onChanged: (value) => onChanged(field.name, value),
        );
      },
    );
  }
}

class _FormFieldEditor extends StatefulWidget {
  const _FormFieldEditor({
    required this.field,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final LexPdfFormField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_FormFieldEditor> createState() => _FormFieldEditorState();
}

class _FormFieldEditorState extends State<_FormFieldEditor> {
  TextEditingController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.field.type == LexPdfFormFieldType.text) {
      _controller = TextEditingController(text: widget.value?.toString() ?? '');
    }
  }

  @override
  void didUpdateWidget(covariant _FormFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null && oldWidget.value != widget.value) {
      final value = widget.value?.toString() ?? '';
      if (_controller!.text != value) _controller!.text = value;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final subtitle = 'Página ${field.pageIndex + 1}${field.isReadOnly ? ' · somente leitura' : ''}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            _editor(field),
          ],
        ),
      ),
    );
  }

  Widget _editor(LexPdfFormField field) {
    switch (field.type) {
      case LexPdfFormFieldType.text:
        return TextField(
          controller: _controller,
          enabled: !field.isReadOnly,
          maxLength: field.maxLength,
          minLines: field.isMultiline ? 3 : 1,
          maxLines: field.isMultiline ? 6 : 1,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        );
      case LexPdfFormFieldType.button:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Marcado'),
          value: widget.value == true,
          onChanged: field.isReadOnly ? null : widget.onChanged,
        );
      case LexPdfFormFieldType.choice:
        final options = field.options;
        final current = widget.value?.toString();
        return DropdownButtonFormField<String>(
          initialValue: options.contains(current) ? current : null,
          items: options
              .map((option) => DropdownMenuItem(value: option, child: Text(option)))
              .toList(growable: false),
          onChanged: field.isReadOnly ? null : widget.onChanged,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        );
      case LexPdfFormFieldType.signature:
        return const Text('Campo de assinatura detectado. Use a ferramenta de assinatura do LexPDF.');
      case LexPdfFormFieldType.unknown:
        return Text(widget.value?.toString() ?? 'Tipo de campo não suportado para edição.');
    }
  }
}
