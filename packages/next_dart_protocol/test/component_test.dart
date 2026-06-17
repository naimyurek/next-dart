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

  // ── F3: library identity fields ─────────────────────────────────────────

  test('NdComponentDef with library/libraryVersion round-trips through JSON',
      () {
    final def = NdComponentDef(
      name: 'Badge',
      params: ['label'],
      body: NdNode(type: 'Text', props: {'text': NdArgRef('label')}),
      library: 'ui_kit',
      libraryVersion: '2.1.0',
    );
    final json = def.toJson();
    expect(json['library'], 'ui_kit');
    expect(json['libraryVersion'], '2.1.0');

    final back = NdComponentDef.fromJson(json);
    expect(back.library, 'ui_kit');
    expect(back.libraryVersion, '2.1.0');
    expect(back.name, 'Badge');
  });

  test(
      'NdComponentDef without library/libraryVersion omits keys in JSON '
      'and reads back as null', () {
    final def = NdComponentDef(
      name: 'Chip',
      params: [],
      body: NdNode(type: 'Text'),
    );
    final json = def.toJson();
    expect(json.containsKey('library'), isFalse);
    expect(json.containsKey('libraryVersion'), isFalse);

    final back = NdComponentDef.fromJson(json);
    expect(back.library, isNull);
    expect(back.libraryVersion, isNull);
  });
}
