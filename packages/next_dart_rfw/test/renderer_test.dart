import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_client/next_dart_client.dart';
import 'package:next_dart_rfw/src/rfw_renderer.dart';

void main() {
  testWidgets('renders catalog widgets and fires actions', (tester) async {
    final captured = <String>[];
    final content = EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        NdNode(type: 'Text', props: {'text': 'Count: 0'}),
        NdNode(type: 'Button', props: {'label': 'Increment'},
            events: {'onPressed': NdActionRef('inc')}),
      ]),
    );

    final renderer = RfwRenderer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => renderer.render(context, content,
              (action, args) async => captured.add(action)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Count: 0'), findsOneWidget);
    expect(find.text('Increment'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(captured, ['inc']);
  });

  testWidgets('renders a Slot as a passthrough of its fallback child',
      (tester) async {
    final content = EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        NdNode(type: 'Slot', props: {'slot': 'a'}, children: [
          NdNode(type: 'Text', props: {'text': 'Loading…'}),
        ]),
      ]),
    );

    final renderer = RfwRenderer();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              renderer.render(context, content, (a, args) async {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Loading…'), findsOneWidget);
  });
}
