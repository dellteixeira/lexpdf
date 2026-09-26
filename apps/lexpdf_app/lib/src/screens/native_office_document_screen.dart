import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:flutter/material.dart';

import '../core/notebook/notebook_document_file_service.dart';

/// Editor Office nativo do LexPDF.
///
/// Não usa WebView, Chromium, JavaScript, Tiptap ou GenOffice. O documento
/// nasce vazio e editável imediatamente; DOCX/RTF/TXT são importados somente
/// quando o usuário escolhe abrir um arquivo.
class NativeOfficeDocumentScreen extends StatefulWidget {
  const NativeOfficeDocumentScreen({super.key});

  @override
  State<NativeOfficeDocumentScreen> createState() =>
      _NativeOfficeDocumentScreenState();
}

class _NativeOfficeDocumentScreenState
    extends State<NativeOfficeDocumentScreen> {
  static const int _maximumOfficeFileBytes = 32 * 1024 * 1024;
  static const NotebookDocumentFileService _fileService =
      NotebookDocumentFileService();

  static const FluentEditorLabels _labels = FluentEditorLabels(
    file: 'Arquivo',
    save: 'Salvar',
    open: 'Abrir',
    exportAs: 'Exportar como',
    microsoftWord: 'Microsoft Word (.docx)',
    libreOffice: 'LibreOffice (.odt)',
    pdf: 'PDF (.pdf)',
    html: 'HTML (.html)',
    markdown: 'Markdown (.md)',
    importHtml: 'Importar HTML',
    importMarkdown: 'Importar Markdown',
    importDocx: 'Importar Word (.docx)',
    importOdt: 'Importar ODT',
    fileSaved: 'Arquivo salvo',
    fileLoaded: 'Arquivo aberto',
    fileLoadError: 'Erro ao abrir arquivo',
    exportSuccess: 'Arquivo exportado',
    exportError: 'Erro ao exportar',
    documentCopied: 'Documento copiado',
    edit: 'Editar',
    undo: 'Desfazer',
    redo: 'Refazer',
    cut: 'Recortar',
    copy: 'Copiar',
    paste: 'Colar',
    pasteWithoutFormatting: 'Colar sem formatação',
    selectAll: 'Selecionar tudo',
    delete: 'Excluir',
    wordCount: 'Palavras',
    characterCount: 'Caracteres',
    insert: 'Inserir',
    link: 'Link',
    image: 'Imagem',
    table: 'Tabela',
    horizontalLine: 'Linha horizontal',
    settings: 'Configurações',
    showStats: 'Mostrar estatísticas',
    documentLanguage: 'Idioma do documento',
    format: 'Formatar',
    text: 'Texto',
    bold: 'Negrito',
    italic: 'Itálico',
    underline: 'Sublinhado',
    strikethrough: 'Tachado',
    superscript: 'Sobrescrito',
    subscript: 'Subscrito',
    smallCaps: 'Versalete',
    styles: 'Estilos',
    align: 'Alinhamento',
    alignLeft: 'Alinhar à esquerda',
    alignCenter: 'Centralizar',
    alignRight: 'Alinhar à direita',
    justify: 'Justificar',
    increaseIndent: 'Aumentar recuo',
    decreaseIndent: 'Diminuir recuo',
    alignAndIndent: 'Alinhamento e recuo',
    lineSpacing: 'Espaçamento',
    paragraphSpacing: 'Espaçamento do parágrafo',
    textColor: 'Cor do texto',
    highlightColor: 'Realce',
    insertLink: 'Inserir link',
    cancel: 'Cancelar',
    confirmButton: 'Confirmar',
    insertButton: 'Inserir',
    apply: 'Aplicar',
    insertImage: 'Inserir imagem',
    or: 'ou',
    done: 'Concluído',
    url: 'URL',
    urlRequired: 'Informe uma URL',
    linkText: 'Texto',
    linkTextHint: 'Texto do link',
    linkTextRequired: 'Informe o texto do link',
    lineHeight: 'Altura da linha',
    spacingBefore: 'Espaço antes',
    spacingAfter: 'Espaço depois',
    imageUrl: 'URL da imagem',
    dragImageHere: 'Arraste uma imagem ou toque para escolher',
    clickToChooseImage: 'Escolher imagem',
    imageSelected: 'Imagem selecionada',
    fileReadError: 'Erro ao ler arquivo',
    chooseListMarkerType: 'Tipo de lista',
    all: 'Todos',
    bullets: 'Marcadores',
    numbers: 'Numeração',
    checkboxes: 'Caixas de seleção',
    replaceImage: 'Substituir imagem',
    replaceLink: 'Substituir link',
    deleteImage: 'Excluir',
    deleteLink: 'Excluir',
    goToLink: 'Abrir link',
    insertRowAbove: 'Inserir linha acima',
    insertRowBelow: 'Inserir linha abaixo',
  );

  late final FluentDocument _document;
  bool _busy = false;
  bool _dirty = false;
  bool _suppressDirty = false;
  bool _legacyDocAvailable = false;
  String _documentName = 'Sem título.docx';

  @override
  void initState() {
    super.initState();
    _document = _blankDocument();
    _document.registry.attach(_document);
    _document.addListener(_onDocumentChanged);
    _loadCapabilities();
  }

  FluentDocument _blankDocument() {
    final document = FluentDocument(
      content: Root(nodes: [Paragraph(text: '')]),
    );
    document.pendingFontFamily = 'Arial';
    document.pendingFontSize = 12;
    document.pendingTextAlign = 'left';
    return document;
  }

  Future<void> _loadCapabilities() async {
    final available = await _fileService.supportsLegacyDoc();
    if (mounted) setState(() => _legacyDocAvailable = available);
  }

  void _onDocumentChanged() {
    if (_suppressDirty || _dirty || !mounted || _document.cursorOnlyChange) {
      return;
    }
    setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _document.removeListener(_onDocumentChanged);
    _document.registry.detach(_document);
    _document.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Descartar alterações?'),
            content: const Text(
              'O documento atual possui alterações que ainda não foram salvas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _newDocument() async {
    if (_busy || !await _confirmDiscardIfNeeded()) return;
    _suppressDirty = true;
    try {
      _document.loadContent(Root(nodes: [Paragraph(text: '')]));
      _document.pendingFontFamily = 'Arial';
      _document.pendingFontSize = 12;
      _document.pendingTextAlign = 'left';
      _document.clearUndoRedo();
      if (!mounted) return;
      setState(() {
        _documentName = 'Sem título.docx';
        _dirty = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _document.requestEditorFocus();
      });
    } finally {
      _suppressDirty = false;
    }
  }

  XTypeGroup get _openTypes => XTypeGroup(
        label: 'Documentos de texto',
        extensions: [
          'docx',
          'rtf',
          'txt',
          if (_legacyDocAvailable) 'doc',
        ],
      );

  Future<void> _openDocument() async {
    if (_busy || !await _confirmDiscardIfNeeded()) return;
    final selected = await openFile(
      acceptedTypeGroups: [_openTypes],
      confirmButtonText: 'Abrir',
    );
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      final length = await selected.length();
      if (length > _maximumOfficeFileBytes) {
        throw StateError('Arquivo excede o limite seguro de 32 MB.');
      }
      final extension = selected.name.contains('.')
          ? selected.name.split('.').last.toLowerCase()
          : '';
      final root = await _fileService.importBytes(
        await selected.readAsBytes(),
        extension,
      );

      _suppressDirty = true;
      _document.loadContent(root);
      _document.clearUndoRedo();
      if (!mounted) return;
      setState(() {
        _documentName =
            selected.name.isEmpty ? 'documento.$extension' : selected.name;
        _dirty = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _document.requestEditorFocus();
      });
    } catch (error) {
      _show('Não foi possível abrir o documento: $error');
    } finally {
      _suppressDirty = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDocx() => _saveAs('docx');

  Future<void> _saveAs(String extension) async {
    if (_busy) return;
    final ext = extension.toLowerCase();
    final base = _documentName.toLowerCase().endsWith('.$ext')
        ? _documentName.substring(0, _documentName.length - ext.length - 1)
        : _documentName.contains('.')
            ? _documentName.substring(0, _documentName.lastIndexOf('.'))
            : _documentName;
    final safeBase = base.trim().isEmpty ? 'documento' : base.trim();

    final location = await getSaveLocation(
      suggestedName: '$safeBase.$ext',
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
      ],
      confirmButtonText: 'Salvar',
    );
    if (location == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await _fileService.exportBytes(_document, ext);
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _documentName = location.path
            .split(Platform.pathSeparator)
            .last;
        _dirty = false;
      });
      _show('Documento salvo com sucesso.');
    } catch (error) {
      _show('Não foi possível salvar .$ext: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (!await _confirmDiscardIfNeeded() || !mounted) return;
    Navigator.of(context).pop();
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Voltar',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _documentName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('•'),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Novo documento',
              onPressed: _busy ? null : _newDocument,
              icon: const Icon(Icons.note_add_outlined),
            ),
            IconButton(
              tooltip: 'Abrir documento',
              onPressed: _busy ? null : _openDocument,
              icon: const Icon(Icons.file_open_outlined),
            ),
            IconButton(
              tooltip: 'Desfazer',
              onPressed: _busy || !_document.canUndo
                  ? null
                  : () {
                      _document.undo();
                      setState(() {});
                    },
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Refazer',
              onPressed: _busy || !_document.canRedo
                  ? null
                  : () {
                      _document.redo();
                      setState(() {});
                    },
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Salvar DOCX',
              onPressed: _busy ? null : _saveDocx,
              icon: const Icon(Icons.save_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'Salvar como',
              enabled: !_busy,
              onSelected: (value) => _saveAs(value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'docx', child: Text('DOCX')),
                PopupMenuItem(value: 'rtf', child: Text('RTF')),
                PopupMenuItem(value: 'txt', child: Text('TXT')),
                PopupMenuItem(value: 'pdf', child: Text('PDF')),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Theme(
                  data: ThemeData.light(useMaterial3: true).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF2F66B3),
                      onPrimary: Colors.white,
                      surface: Colors.white,
                      onSurface: Color(0xFF202124),
                      surfaceContainerHighest: Color(0xFFF3F5F8),
                      outline: Color(0xFFB8BEC7),
                    ),
                  ),
                  child: FluentDocumentWidget(
                    document: _document,
                    labels: _labels,
                    toolbarMode: FluentToolbarMode.fixed,
                    maxWidth: 900,
                  ),
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.72),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
