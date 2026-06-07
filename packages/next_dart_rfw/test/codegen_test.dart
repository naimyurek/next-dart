import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_rfw/src/rfw_codegen.dart';
// parseLibraryFile is intentionally NOT exported by package:rfw/rfw.dart
// (it is hidden there to discourage client-side text parsing); it lives in
// package:rfw/formats.dart, which also exports the RemoteWidgetLibrary model.
import 'package:rfw/formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated text parses as a valid rfw library', () {
    final content = EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(
          type: 'Button',
          props: {'label': 'Increment'},
          events: {'onPressed': NdActionRef('inc')},
        ),
        NdNode(type: 'ProductCard',
            props: {'title': 'Shoe', 'price': r'$10', 'id': 7}),
      ]),
      components: [
        NdComponentDef(name: 'ProductCard', params: ['title', 'price', 'id'],
          body: NdNode(type: 'Card', children: [
            NdNode(type: 'Column', children: [
              NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
              NdNode(type: 'Text', props: {'text': NdArgRef('price')}),
              NdNode(type: 'Button', props: {'label': 'Buy'},
                events: {'onPressed': NdActionRef('buy', {'id': NdArgRef('id')})}),
            ]),
          ]),
        ),
      ],
    );
    final text = generateRfwText(content);
    // Must parse without throwing.
    final lib = parseLibraryFile(text);
    expect(lib.widgets.map((w) => w.name), contains('root'));
    expect(lib.widgets.map((w) => w.name), contains('ProductCard'));
  });

  test('strings are escaped and arg refs become args.x', () {
    final content = EnvelopeContent(
      root: NdNode(type: 'Text', props: {'text': r'a"b'}),
      components: [
        NdComponentDef(name: 'C', params: ['t'],
            body: NdNode(type: 'Text', props: {'text': NdArgRef('t')})),
      ],
    );
    final text = generateRfwText(content);
    expect(text, contains(r'args.t'));
    // The escaped quote survives parsing.
    expect(() => parseLibraryFile(text), returnsNormally);
  });
}
