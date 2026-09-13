from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2] if '.github' in str(Path(__file__).resolve()) else Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def write(rel, text):
    (ROOT / rel).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 occurrence, found {count}')
    return text.replace(old, new, 1)


def sub_once(text, pattern, replacement, label, flags=0):
    result, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected exactly 1 regex match, found {count}')
    return result

path = 'apps/lexpdf_app/lib/src/screens/layered_notebook_screen.dart'
text = read(path)
new_viewport = r'''  Widget _buildPageViewport(InkNotebookPage page) {
    final document = _richDocument;
    return ColoredBox(
      key: _pageViewportKey,
      color: const Color(0xFFD9DDE2),
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              transformationController: _pageTransformController,
              minScale: 0.25,
              maxScale: 4,
              panEnabled: _handMode,
              scaleEnabled: _handMode,
              boundaryMargin: const EdgeInsets.all(220),
              onInteractionEnd: (_) {
                final scale = _pageTransformController.value.getMaxScaleOnAxis();
                if (mounted) {
                  setState(() => _zoom = scale.clamp(0.25, 4.0));
                }
              },
              child: Center(
                child: AspectRatio(
                  aspectRatio: page.width / page.height,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                      border: Border.all(color: const Color(0xFFC6C9CE)),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 5,
                          offset: Offset(0, 2),
                          color: Color(0x26000000),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NotebookPageBackground(background: page.background),
                        NotebookObjectLayer(
                          objects: _backgroundObjects,
                          enabled: false,
                          selectedId: null,
                          onObjectChanged: (_) {},
                          onObjectDoubleTap: (_) {},
                          onSelectionChanged: (_) {},
                        ),
                        if (document != null)
                          NotebookRichDocumentSurface(
                            key: ValueKey('rich-document-${page.id}'),
                            document: document,
                            enabled: _textMode && !_handMode,
                          ),
                        NotebookLayerInkView(strokes: _backgroundStrokes),
                        IgnorePointer(
                          ignoring: !_canEditActiveLayer ||
                              _textMode ||
                              _pointerMode ||
                              _handMode,
                          child: InkCanvas(
                            key: _canvasKey,
                            initialStrokes: _activeLayer?.isVisible == true
                                ? _activeStrokes
                                : const [],
                            pageId: page.id,
                            tool: _tool,
                            colorValue: _colorValue,
                            strokeWidth: _effectiveWidth,
                            stylusOnly: _stylusOnly,
                            eraserMode: _eraserMode,
                            lassoMode: _lassoMode,
                            onWillMutate: _recordHistory,
                            onStrokeCompleted: _onStrokeCompleted,
                            onStrokeUpdated: _onStrokeUpdated,
                            onStrokeErased: _onStrokeErased,
                            onSelectionChanged: (ids) {
                              if (mounted) {
                                setState(() => _selectionCount = ids.length);
                              }
                            },
                          ),
                        ),
                        NotebookObjectLayer(
                          objects: _activeLayer?.isVisible == true
                              ? _activeObjects
                              : const [],
                          enabled: !_textMode &&
                              _pointerMode &&
                              !_handMode &&
                              _canEditActiveLayer,
                          selectedId: _selectedObjectId,
                          onObjectChanged: _onObjectChanged,
                          onSelectionChanged: (id) {
                            if (!mounted) return;
                            setState(() => _selectedObjectId = id);
                          },
                        ),
                        NotebookRulerOverlay(enabled: _rulerMode),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_textMode && _pointerMode)
            Positioned(
              left: 16,
              bottom: 16,
              child: Material(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    _selectedObjectId == null
                        ? 'Selecionar: clique em uma imagem ou forma'
                        : 'Objeto selecionado: arraste para mover ou use os controles acima',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

'''
text = sub_once(text, r"  Widget _buildPageViewport\(InkNotebookPage page\) \{.*?\n  void _zoomBy", new_viewport + '  void _zoomBy', 'replace page viewport layer model', re.S)
text = replace_once(text, '''      onPointerModeChanged: (value) => setState(() {
        _pointerMode = value;
        if (value) {''', '''      onPointerModeChanged: (value) => setState(() {
        _pointerMode = value;
        if (value) {
          _textMode = false;''', 'object mode disables text mode')
text = replace_once(text, '''      onHandModeChanged: (value) => setState(() {
        _handMode = value;
        if (value) {''', '''      onHandModeChanged: (value) => setState(() {
        _handMode = value;
        if (value) {
          _textMode = false;''', 'hand mode disables text mode')
text = replace_once(text, '''      onToolChanged: (value) => setState(() {
        _tool = value;
        _eraserMode = false;''', '''      onToolChanged: (value) => setState(() {
        _tool = value;
        _textMode = false;
        _eraserMode = false;''', 'drawing tool disables text mode')
text = replace_once(text, '''      onEraserModeChanged: (value) => setState(() {
        _eraserMode = value;
        if (value) {''', '''      onEraserModeChanged: (value) => setState(() {
        _eraserMode = value;
        if (value) {
          _textMode = false;''', 'eraser disables text mode')
text = replace_once(text, '''      onLassoModeChanged: (value) => setState(() {
        _lassoMode = value;
        _eraserMode = false;''', '''      onLassoModeChanged: (value) => setState(() {
        _lassoMode = value;
        if (value) _textMode = false;
        _eraserMode = false;''', 'lasso disables text mode')
text = replace_once(text, '''      onEditTextObject: () {
        if (selectedObject != null) _beginTextEditing(selectedObject);
      },''', '''      onEditTextObject: _activateTextMode,''', 'remove object text editor callback')
write(path, text)
