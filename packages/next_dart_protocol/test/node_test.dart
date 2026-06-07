import 'package:next_dart_protocol/src/node.dart';
import 'package:test/test.dart';

void main() {
  test('NdNode round-trips through JSON', () {
    final node = NdNode(
      type: 'Column',
      children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(
          type: 'Button',
          props: {'label': 'Increment'},
          events: {'onPressed': NdActionRef('inc')},
        ),
      ],
    );
    final json = node.toJson();
    final back = NdNode.fromJson(json);
    expect(back.toJson(), json);
    expect(back.children[1].events['onPressed']!.action, 'inc');
  });

  test('NdArgRef serializes to {\$arg: name}', () {
    final n = NdNode(type: 'Text', props: {'text': NdArgRef('title')});
    expect(n.toJson()['props'], {'text': {r'$arg': 'title'}});
    final back = NdNode.fromJson(n.toJson());
    expect(back.props['text'], isA<NdArgRef>());
    expect((back.props['text'] as NdArgRef).name, 'title');
  });

  test('NdActionRef carries args, including NdArgRef values', () {
    final a = NdActionRef('buy', {'id': NdArgRef('id')});
    final back = NdActionRef.fromJson(a.toJson());
    expect(back.action, 'buy');
    expect((back.args['id'] as NdArgRef).name, 'id');
  });
}
