import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/input/ime_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

FluentDocument _documentWithText(String text) {
  final document = FluentDocument(
    content: Root(nodes: [Paragraph(text: text)]),
  );
  document.eventHandler.document = document;
  document.imeHandler.attachInput(document);
  final paragraph = document.content.nodes.first as Paragraph;
  final fragment = paragraph.fragments.first as Fragment;
  document.cursor.moveTo(fragment.id, fragment.text.length);
  return document;
}

Fragment _firstFragment(FluentDocument document) {
  final paragraph = document.content.nodes.first as Paragraph;
  return paragraph.fragments.first as Fragment;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FluentTextInputHandler().detachInput();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    FluentTextInputHandler().detachInput();
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android commits composed word before a space insertion', () {
    final document = _documentWithText('Teste ');
    final handler = document.imeHandler;

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste ',
        textInserted: 'd',
        insertionOffset: 6,
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 6, end: 7),
      ),
    ]);
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste d',
        textInserted: 'e',
        insertionOffset: 7,
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 6, end: 8),
      ),
    ]);
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste de',
        textInserted: 's',
        insertionOffset: 8,
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 6, end: 9),
      ),
    ]);
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste des',
        textInserted: 'c',
        insertionOffset: 9,
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 6, end: 10),
      ),
    ]);
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste desc',
        textInserted: 'r',
        insertionOffset: 10,
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange(start: 6, end: 11),
      ),
    ]);
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste descr',
        textInserted: 'i',
        insertionOffset: 11,
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange(start: 6, end: 12),
      ),
    ]);

    expect(handler.isComposing, isTrue);
    expect(_firstFragment(document).text, 'Teste ');

    // Samsung Keyboard/Gboard can finalize the word by sending the separator
    // as a normal insertion with an empty composing range.
    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste descri',
        textInserted: ' ',
        insertionOffset: 12,
        selection: TextSelection.collapsed(offset: 13),
        composing: TextRange.empty,
      ),
    ]);

    expect(handler.isComposing, isFalse);
    expect(_firstFragment(document).text, 'Teste descri ');
  });

  test('Android commits composition on a standalone non-text update', () {
    final document = _documentWithText('Teste ');
    final handler = document.imeHandler;

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste ',
        textInserted: 'descri',
        insertionOffset: 6,
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange(start: 6, end: 12),
      ),
    ]);

    expect(handler.isComposing, isTrue);
    expect(_firstFragment(document).text, 'Teste ');

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: 'Teste descri',
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange.empty,
      ),
    ]);

    expect(handler.isComposing, isFalse);
    expect(_firstFragment(document).text, 'Teste descri');
  });

  test('Android backspace inside preedit does not erase committed prefix', () {
    final document = _documentWithText('Teste ');
    final handler = document.imeHandler;

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste ',
        textInserted: 'descri',
        insertionOffset: 6,
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange(start: 6, end: 12),
      ),
    ]);

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaDeletion(
        oldText: 'Teste descri',
        deletedRange: TextRange(start: 11, end: 12),
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange(start: 6, end: 11),
      ),
    ]);

    expect(handler.isComposing, isTrue);
    expect(handler.preeditText, 'descr');
    expect(_firstFragment(document).text, 'Teste ');

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: 'Teste descr',
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange.empty,
      ),
    ]);

    expect(_firstFragment(document).text, 'Teste descr');
  });

  test('Android autocorrect can finalize a composing word by replacement', () {
    final document = _documentWithText('Teste ');
    final handler = document.imeHandler;

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: 'Teste ',
        textInserted: 'descri',
        insertionOffset: 6,
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange(start: 6, end: 12),
      ),
    ]);

    handler.updateEditingValueWithDeltas([
      const TextEditingDeltaReplacement(
        oldText: 'Teste descri',
        replacementText: 'descrição',
        replacedRange: TextRange(start: 6, end: 12),
        selection: TextSelection.collapsed(offset: 15),
        composing: TextRange.empty,
      ),
    ]);

    expect(handler.isComposing, isFalse);
    expect(_firstFragment(document).text, 'Teste descrição');
  });
}
