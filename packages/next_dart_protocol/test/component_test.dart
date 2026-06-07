import 'package:next_dart_protocol/src/node.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:test/test.dart';

void main() {
  test('NdComponentDef round-trips through JSON', () {
    final def = NdComponentDef(
      name: 'ProductCard',
      params: ['title', 'price', 'id'],
      body: NdNode(type: 'Card', children: [
        NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
      ]),
    );
    final back = NdComponentDef.fromJson(def.toJson());
    expect(back.name, 'ProductCard');
    expect(back.params, ['title', 'price', 'id']);
    expect((back.body.children[0].props['text'] as NdArgRef).name, 'title');
  });
}
