// packages/next_dart_basic/test/expander_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_basic/next_dart_basic.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// A ProductCard component def:
  ///   ProductCard(title, price, id) →
  ///     Column([
  ///       Text(text: $title),
  ///       Text(text: $price),
  ///       Button(label: 'Buy', events.onPressed: Action('buy', {id: $id})),
  ///     ])
  NdComponentDef productCardDef() => const NdComponentDef(
        name: 'ProductCard',
        params: ['title', 'price', 'id'],
        body: NdNode(
          type: 'Column',
          children: [
            NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
            NdNode(type: 'Text', props: {'text': NdArgRef('price')}),
            NdNode(
              type: 'Button',
              props: {'label': 'Buy'},
              events: {
                'onPressed': NdActionRef('buy', {'id': NdArgRef('id')}),
              },
            ),
          ],
        ),
      );

  group('expand — flat composite', () {
    test('substitutes title and price into Text props', () {
      final def = productCardDef();
      final byName = {def.name: def};

      final instance = NdNode(
        type: 'ProductCard',
        props: {'title': 'Shoe', 'price': r'$10', 'id': 7},
      );

      final result = expand(instance, byName);

      expect(result.type, equals('Column'));
      final texts = result.children
          .where((c) => c.type == 'Text')
          .map((c) => c.props['text'])
          .toList();
      expect(texts, containsAll(['Shoe', r'$10']));
    });

    test('substitutes id into Button onPressed action args', () {
      final def = productCardDef();
      final byName = {def.name: def};

      final instance = NdNode(
        type: 'ProductCard',
        props: {'title': 'Shoe', 'price': r'$10', 'id': 7},
      );

      final result = expand(instance, byName);

      final button =
          result.children.firstWhere((c) => c.type == 'Button');
      expect(button.events['onPressed']?.action, equals('buy'));
      expect(button.events['onPressed']?.args['id'], equals(7));
    });

    test('NdArgRef is fully replaced — no NdArgRef remains in expanded tree',
        () {
      final def = productCardDef();
      final byName = {def.name: def};

      final instance = NdNode(
        type: 'ProductCard',
        props: {'title': 'Shoe', 'price': r'$10', 'id': 7},
      );

      final result = expand(instance, byName);

      void assertNoArgRefs(NdNode node) {
        for (final v in node.props.values) {
          expect(v, isNot(isA<NdArgRef>()),
              reason: 'prop still contains NdArgRef in ${node.type}');
        }
        for (final ref in node.events.values) {
          for (final v in ref.args.values) {
            expect(v, isNot(isA<NdArgRef>()),
                reason: 'event arg still contains NdArgRef in ${node.type}');
          }
        }
        for (final child in node.children) {
          assertNoArgRefs(child);
        }
      }

      assertNoArgRefs(result);
    });
  });

  group('expand — nested composites', () {
    /// A wrapper component: CardWrapper(title, price, id) → Card(child: ProductCard(title,price,id))
    NdComponentDef cardWrapperDef() => NdComponentDef(
          name: 'CardWrapper',
          params: const ['title', 'price', 'id'],
          body: NdNode(
            type: 'Card',
            children: [
              NdNode(
                type: 'ProductCard',
                props: {
                  'title': const NdArgRef('title'),
                  'price': const NdArgRef('price'),
                  'id': const NdArgRef('id'),
                },
              ),
            ],
          ),
        );

    test('nested composite expands both layers', () {
      final productDef = productCardDef();
      final wrapperDef = cardWrapperDef();
      final byName = {productDef.name: productDef, wrapperDef.name: wrapperDef};

      final instance = NdNode(
        type: 'CardWrapper',
        props: {'title': 'Hat', 'price': r'$5', 'id': 99},
      );

      final result = expand(instance, byName);

      // Outer wrapper resolves to Card > Column
      expect(result.type, equals('Card'));
      expect(result.children.first.type, equals('Column'));

      final column = result.children.first;
      final texts = column.children
          .where((c) => c.type == 'Text')
          .map((c) => c.props['text'])
          .toList();
      expect(texts, containsAll(['Hat', r'$5']));

      final button =
          column.children.firstWhere((c) => c.type == 'Button');
      expect(button.events['onPressed']?.args['id'], equals(99));
    });
  });

  group('expand — primitives pass through unchanged', () {
    test('primitive node is returned with children recursed', () {
      final byName = <String, NdComponentDef>{};
      const node = NdNode(
        type: 'Column',
        children: [
          NdNode(type: 'Text', props: {'text': 'Hello'}),
        ],
      );

      final result = expand(node, byName);

      expect(result.type, equals('Column'));
      expect(result.children.first.type, equals('Text'));
      expect(result.children.first.props['text'], equals('Hello'));
    });
  });
}
