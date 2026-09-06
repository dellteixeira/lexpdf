import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/annotations/saved_signature.dart';
import '../core/storage/local_signature_store.dart';

Future<SavedSignature?> showSignatureLibraryDialog(
  BuildContext context,
  LocalSignatureStore store,
) {
  return showDialog<SavedSignature>(
    context: context,
    builder: (_) => _SignatureLibraryDialog(store: store),
  );
}

class _SignatureLibraryDialog extends StatefulWidget {
  const _SignatureLibraryDialog({required this.store});
  final LocalSignatureStore store;

  @override
  State<_SignatureLibraryDialog> createState() => _SignatureLibraryDialogState();
}

class _SignatureLibraryDialogState extends State<_SignatureLibraryDialog> {
  List<SavedSignature> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await widget.store.listAll();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final signature = await showDialog<SavedSignature>(
      context: context,
      builder: (_) => const _SignatureCaptureDialog(),
    );
    if (signature == null) return;
    await widget.store.upsert(signature);
    await _reload();
  }

  Future<void> _delete(SavedSignature signature) async {
    await widget.store.delete(signature.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Biblioteca de assinaturas'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(
                    child: Text('Nenhuma assinatura salva. Crie a primeira.'),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        child: ListTile(
                          leading: SizedBox(
                            width: 120,
                            height: 48,
                            child: CustomPaint(
                              painter: SignaturePreviewPainter(signature: item),
                            ),
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.strokes.length} traço(s) · ${item.strokeWidth.toStringAsFixed(1)} px',
                          ),
                          onTap: () => Navigator.of(context).pop(item),
                          trailing: IconButton(
                            tooltip: 'Excluir assinatura',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(item),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.draw_outlined),
          label: const Text('Nova assinatura'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _SignatureCaptureDialog extends StatefulWidget {
  const _SignatureCaptureDialog();

  @override
  State<_SignatureCaptureDialog> createState() => _SignatureCaptureDialogState();
}

class _SignatureCaptureDialogState extends State<_SignatureCaptureDialog> {
  final TextEditingController _name = TextEditingController(text: 'Minha assinatura');
  final List<List<SignaturePoint>> _strokes = [];
  List<SignaturePoint>? _current;
  double _width = 3;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  SignaturePoint _point(Offset local, Size size) => SignaturePoint(
        size.width <= 0 ? 0 : (local.dx / size.width).clamp(0.0, 1.0),
        size.height <= 0 ? 0 : (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _down(PointerDownEvent event, Size size) {
    final stroke = <SignaturePoint>[_point(event.localPosition, size)];
    setState(() {
      _current = stroke;
      _strokes.add(stroke);
    });
  }

  void _move(PointerMoveEvent event, Size size) {
    final stroke = _current;
    if (stroke == null) return;
    stroke.add(_point(event.localPosition, size));
    setState(() {});
  }

  void _up(PointerEvent event) {
    _current = null;
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _current = null;
    });
  }

  void _save() {
    final usable = _strokes.where((stroke) => stroke.length >= 2).toList();
    if (_name.text.trim().isEmpty || usable.isEmpty) return;
    final now = DateTime.now().toUtc();
    Navigator.of(context).pop(
      SavedSignature(
        id: 'signature-${now.microsecondsSinceEpoch.toRadixString(36)}',
        name: _name.text.trim(),
        strokes: usable,
        colorValue: 0xFF111111,
        strokeWidth: _width,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova assinatura manuscrita'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _down(event, size),
                    onPointerMove: (event) => _move(event, size),
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: CustomPaint(
                      painter: _CapturePainter(
                        strokes: _strokes,
                        strokeWidth: _width,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                const Text('Espessura'),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 8,
                    value: _width,
                    onChanged: (value) => setState(() => _width = value),
                  ),
                ),
                Text(_width.toStringAsFixed(1)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _clear, child: const Text('Limpar')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salvar assinatura')),
      ],
    );
  }
}

class _CapturePainter extends CustomPainter {
  const _CapturePainter({required this.strokes, required this.strokeWidth});
  final List<List<SignaturePoint>> strokes;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()
        ..moveTo(stroke.first.x * size.width, stroke.first.y * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CapturePainter oldDelegate) => true;
}

class SignaturePreviewPainter extends CustomPainter {
  const SignaturePreviewPainter({required this.signature});
  final SavedSignature signature;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(signature.colorValue)
      ..strokeWidth = math.max(1.0, signature.strokeWidth * 0.75)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in signature.strokes) {
      if (stroke.length < 2) continue;
      final path = Path()
        ..moveTo(stroke.first.x * size.width, stroke.first.y * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.x * size.width, point.y * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePreviewPainter oldDelegate) =>
      oldDelegate.signature != signature;
}
