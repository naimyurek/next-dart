import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/renderer.dart';
import 'package:next_dart_client/src/view.dart';

class _FakeRenderer extends NextDartRenderer {
  @override
  Widget render(BuildContext context, EnvelopeContent content, NdActionDispatcher dispatch) {
    final label = content.root.props['text'] as String;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onTap: () => dispatch('inc', const {}),
        child: Text(label),
      ),
    );
  }
}

class _FakeSource extends NextDartSource {
  int count = 0;
  @override
  Future<EnvelopeContent> fetchPage(String route) async =>
      EnvelopeContent(root: NdNode(type: 'Text', props: {'text': 'Count: $count'}));
  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args, {required String route}) async {
    count++;
    return EnvelopeContent(root: NdNode(type: 'Text', props: {'text': 'Count: $count'}));
  }
}

void main() {
  testWidgets('view renders page then re-renders after an action', (tester) async {
    await tester.pumpWidget(NextDartView(
      source: _FakeSource(),
      route: '/',
      renderer: _FakeRenderer(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.text('Count: 0'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);
  });
}
