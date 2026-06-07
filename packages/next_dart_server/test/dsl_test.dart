import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/src/dsl.dart';
import 'package:next_dart_server/src/component_dsl.dart';
import 'package:test/test.dart';

void main() {
  test('primitive builders produce the expected nodes', () {
    final n = ndColumn([
      ndText('Count: 0'),
      ndButton(label: 'Increment', onPressed: action('inc')),
    ]);
    expect(n.type, 'Column');
    expect(n.children[0].props['text'], 'Count: 0');
    expect(n.children[1].events['onPressed']!.action, 'inc');
  });

  test('ndText accepts an arg ref for component bodies', () {
    final n = ndText(ndArg('title'));
    expect((n.props['text'] as NdArgRef).name, 'title');
  });

  test('ndComponent builds a NdComponentDef from a param-aware builder', () {
    final def = ndComponent('ProductCard', ['title', 'price', 'id'], (a) {
      return ndCard(
        child: ndColumn([
          ndText(a('title')),
          ndText(a('price')),
          ndButton(label: 'Buy', onPressed: action('buy', {'id': a('id')})),
        ]),
      );
    });
    expect(def.name, 'ProductCard');
    expect(def.params, ['title', 'price', 'id']);
    // body = Card > Column > [Text, Text, Button]
    final col = def.body.children[0];
    expect(col.type, 'Column');
    expect((col.children[0].props['text'] as NdArgRef).name, 'title');
    expect((col.children[2].events['onPressed']!.args['id'] as NdArgRef).name, 'id');
  });

  test('ndUse instantiates a component by name with props', () {
    final n = ndUse('ProductCard', {'title': 'Shoe', 'price': r'$10', 'id': 7});
    expect(n.type, 'ProductCard');
    expect(n.props['title'], 'Shoe');
    expect(n.props['id'], 7);
  });
}
