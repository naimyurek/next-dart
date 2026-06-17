// packages/next_dart_basic/test/basic_renderer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_basic/next_dart_basic.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps the renderer output in a minimal MaterialApp so widgets that require
/// Material/Directionality ancestors (ElevatedButton, Text, etc.) work.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

EnvelopeContent _content(NdNode root, {List<NdComponentDef> components = const []}) =>
    EnvelopeContent(root: root, components: components);

NdActionDispatcher _noopDispatch() => (_, __) async {};

void main() {
  final renderer = BasicRenderer();

  // ---------------------------------------------------------------------------
  // Primitive widget smoke tests
  // ---------------------------------------------------------------------------

  group('BasicRenderer — primitives', () {
    testWidgets('renders Text widget', (tester) async {
      final content = _content(
        const NdNode(type: 'Text', props: {'text': 'Hello'}),
      );

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('renders Column with children', (tester) async {
      final content = _content(const NdNode(
        type: 'Column',
        children: [
          NdNode(type: 'Text', props: {'text': 'A'}),
          NdNode(type: 'Text', props: {'text': 'B'}),
        ],
      ));

      late Widget widget;
      await tester.pumpWidget(
        Builder(builder: (ctx) {
          widget = renderer.render(ctx, content, _noopDispatch());
          return _wrap(widget);
        }),
      );
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('renders Card wrapping a Text child', (tester) async {
      final content = _content(const NdNode(
        type: 'Card',
        children: [
          NdNode(type: 'Text', props: {'text': 'CardText'}),
        ],
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('CardText'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('renders Padding with a child', (tester) async {
      final content = _content(const NdNode(
        type: 'Padding',
        props: {'all': 8.0},
        children: [
          NdNode(type: 'Text', props: {'text': 'PadMe'}),
        ],
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('PadMe'), findsOneWidget);
      expect(find.byType(Padding), findsWidgets);
    });

    testWidgets('renders Button with label', (tester) async {
      final content = _content(NdNode(
        type: 'Button',
        props: const {'label': 'Click me'},
        events: {'onPressed': const NdActionRef('doThing')},
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('Click me'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Button dispatch test
  // ---------------------------------------------------------------------------

  group('BasicRenderer — Button dispatch', () {
    testWidgets('tapping Button calls dispatcher with correct action + args',
        (tester) async {
      String? capturedAction;
      Map<String, Object?>? capturedArgs;

      final content = _content(NdNode(
        type: 'Button',
        props: const {'label': 'Buy'},
        events: {
          'onPressed': const NdActionRef('purchase', {'sku': 'ABC-123'}),
        },
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) => _wrap(
              renderer.render(ctx, content, (action, args) async {
                capturedAction = action;
                capturedArgs = args;
              }),
            )),
      );
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(capturedAction, equals('purchase'));
      expect(capturedArgs, equals({'sku': 'ABC-123'}));
    });
  });

  // ---------------------------------------------------------------------------
  // Composite component expansion
  // ---------------------------------------------------------------------------

  group('BasicRenderer — composite components', () {
    /// ProductCard component: title, price, id →
    ///   Column([Text(title), Text(price), Button(Buy, {id})])
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

    testWidgets('composite renders inner Text widgets (Shoe / \$10)',
        (tester) async {
      final content = _content(
        const NdNode(
          type: 'ProductCard',
          props: {'title': 'Shoe', 'price': r'$10', 'id': 7},
        ),
        components: [productCardDef()],
      );

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('Shoe'), findsOneWidget);
      expect(find.text(r'$10'), findsOneWidget);
      expect(find.text('Buy'), findsOneWidget);
    });

    testWidgets('composite Button dispatches id arg correctly', (tester) async {
      Object? capturedId;

      final content = _content(
        const NdNode(
          type: 'ProductCard',
          props: {'title': 'Shoe', 'price': r'$10', 'id': 42},
        ),
        components: [productCardDef()],
      );

      await tester.pumpWidget(
        Builder(builder: (ctx) => _wrap(
              renderer.render(ctx, content, (action, args) async {
                capturedId = args['id'];
              }),
            )),
      );
      await tester.pump();

      await tester.tap(find.text('Buy'));
      await tester.pump();

      expect(capturedId, equals(42));
    });
  });

  // ---------------------------------------------------------------------------
  // Slot (streaming placeholder) renders its child
  // ---------------------------------------------------------------------------

  group('BasicRenderer — Slot', () {
    testWidgets('renders a Slot\'s fallback child', (tester) async {
      final content = _content(const NdNode(
        type: 'Slot',
        props: {'slot': 'a'},
        children: [
          NdNode(type: 'Text', props: {'text': 'Loading…'}),
        ],
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets('an empty Slot renders without throwing', (tester) async {
      final content = _content(const NdNode(type: 'Slot', props: {'slot': 'a'}));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Unknown widget fallback
  // ---------------------------------------------------------------------------

  group('BasicRenderer — unknown widget fallback', () {
    testWidgets('unknown type shows fallback text without throwing',
        (tester) async {
      final content = _content(
        const NdNode(type: 'SuperGizmo', props: {'x': 1}),
      );

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.textContaining('Unknown widget: SuperGizmo'), findsOneWidget);
    });

    testWidgets('unknown type inside Column does not crash page', (tester) async {
      final content = _content(const NdNode(
        type: 'Column',
        children: [
          NdNode(type: 'Text', props: {'text': 'Above'}),
          NdNode(type: 'GizmoXYZ'),
          NdNode(type: 'Text', props: {'text': 'Below'}),
        ],
      ));

      await tester.pumpWidget(
        Builder(builder: (ctx) =>
            _wrap(renderer.render(ctx, content, _noopDispatch()))),
      );
      await tester.pump();

      expect(find.text('Above'), findsOneWidget);
      expect(find.text('Below'), findsOneWidget);
      expect(find.textContaining('Unknown widget: GizmoXYZ'), findsOneWidget);
    });
  });
}
