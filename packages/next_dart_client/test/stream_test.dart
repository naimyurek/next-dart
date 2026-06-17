import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/client.dart';
import 'package:next_dart_client/src/renderer.dart';
import 'package:next_dart_client/src/source.dart';
import 'package:next_dart_client/src/stream_view.dart';
import 'package:next_dart_client/src/patch.dart';

// ---------------------------------------------------------------------------
// applyPatch — pure helper
// ---------------------------------------------------------------------------

EnvelopeContent _treeWithSlot(String slotId) => EnvelopeContent(
      root: NdNode(type: 'Column', children: [
        const NdNode(type: 'Text', props: {'text': 'header'}),
        NdNode(type: kSlotType, props: {kFrameSlot: slotId}, children: const [
          NdNode(type: 'Text', props: {'text': 'Loading…'}),
        ]),
      ]),
    );

void main() {
  group('applyPatch', () {
    test('replaces the matching slot\'s children with [replacement]', () {
      final current = _treeWithSlot('a');
      final out = applyPatch(
          current, 'a', const NdNode(type: 'Text', props: {'text': 'done'}));

      final slot = out.root.children[1];
      expect(slot.type, kSlotType);
      expect(slot.props[kFrameSlot], 'a');
      expect(slot.children.single.props['text'], 'done',
          reason: 'fallback child replaced by the patch root');
    });

    test('non-matching slot id leaves the tree unchanged', () {
      final current = _treeWithSlot('a');
      final out = applyPatch(
          current, 'zzz', const NdNode(type: 'Text', props: {'text': 'done'}));

      final slot = out.root.children[1];
      // Fallback still present, untouched.
      expect(slot.children.single.props['text'], 'Loading…');
    });

    test('preserves data and components on the returned content', () {
      final current = EnvelopeContent(
        root: NdNode(type: kSlotType, props: const {kFrameSlot: 'a'}, children: const [
          NdNode(type: 'Text', props: {'text': 'f'}),
        ]),
        components: const [
          NdComponentDef(name: 'C', params: [], body: NdNode(type: 'Text')),
        ],
        data: const {'kind': 'initial'},
      );
      final out = applyPatch(
          current, 'a', const NdNode(type: 'Text', props: {'text': 'x'}));
      expect(out.components.single.name, 'C');
      expect(out.data['kind'], 'initial');
      expect(out.root.children.single.props['text'], 'x');
    });

    test('replaces a slot nested deep in the tree', () {
      final current = EnvelopeContent(
        root: const NdNode(type: 'Column', children: [
          NdNode(type: 'Card', children: [
            NdNode(type: kSlotType, props: {kFrameSlot: 'deep'}, children: [
              NdNode(type: 'Text', props: {'text': 'wait'}),
            ]),
          ]),
        ]),
      );
      final out = applyPatch(
          current, 'deep', const NdNode(type: 'Text', props: {'text': 'ok'}));
      final slot = out.root.children.single.children.single;
      expect(slot.type, kSlotType);
      expect(slot.children.single.props['text'], 'ok');
    });
  });

  // ---------------------------------------------------------------------------
  // streamPage — real wire seam (server frame bytes -> client decode)
  // ---------------------------------------------------------------------------
  //
  // Mirrors exactly what NextDartApp.stream / the /__stream handler emit: one
  // base64-encoded envelope per line, newline-delimited. This is the seam
  // between server output framing and client consumption.

  test('streamPage decodes newline-delimited base64 frames end-to-end',
      () async {
    final signingKp = await Ed25519().newKeyPair();
    final signingPub = await signingKp.extractPublicKey();
    final secret = SecretKey(List.filled(32, 11));

    Future<List<int>> frame(EnvelopeContent c) => encodeEnvelope(
          content: c,
          route: '/',
          contentVersion: 1,
          minClientVersion: '1.0.0',
          keyId: 'k1',
          secretKey: secret,
          signingKeyPair: signingKp,
        );

    // Build the exact server body: base64(envelope) + "\n" per frame.
    final initialBytes = await frame(EnvelopeContent(
      root: const NdNode(type: 'Column', children: [
        NdNode(type: kSlotType, props: {kFrameSlot: 'a'}, children: [
          NdNode(type: 'Text', props: {'text': 'Loading…'}),
        ]),
      ]),
      data: initialFrameData(),
    ));
    final patchBytes = await frame(EnvelopeContent(
      root: const NdNode(type: 'Text', props: {'text': 'resolved-a'}),
      data: patchFrameData('a'),
    ));
    final body = '${base64.encode(initialBytes)}\n'
        '${base64.encode(patchBytes)}\n';

    final mock = MockClient.streaming((req, bodyStream) async {
      expect(req.url.path, '/__stream');
      expect(req.url.queryParameters['route'], '/');
      return http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        200,
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    });

    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );

    final frames = await client.streamPage('/').toList();
    expect(frames.length, 2);
    expect(frameKind(frames[0].data), kFrameInitial);
    expect(frames[0].root.children.single.type, kSlotType);
    expect(frameKind(frames[1].data), kFramePatch);
    expect(frameSlot(frames[1].data), 'a');
    expect(frames[1].root.props['text'], 'resolved-a');
  });

  test('streamPage throws DecodeError on a non-200 stream response', () async {
    final signingKp = await Ed25519().newKeyPair();
    final signingPub = await signingKp.extractPublicKey();
    final secret = SecretKey(List.filled(32, 11));
    final mock = MockClient.streaming((req, bodyStream) async =>
        http.StreamedResponse(Stream.value(utf8.encode('nope')), 404));
    final client = NextDartClient(
      baseUrl: Uri.parse('http://test'),
      signingPublicKey: signingPub,
      secretKey: secret,
      httpClient: mock,
    );
    expect(() => client.streamPage('/').toList(), throwsA(isA<DecodeError>()));
  });

  // ---------------------------------------------------------------------------
  // NextDartStreamView — widget
  // ---------------------------------------------------------------------------

  testWidgets('stream view shows fallback then swaps in patch content',
      (tester) async {
    final controller = StreamController<EnvelopeContent>();
    final source = _FakeStreamSource(controller.stream);

    await tester.pumpWidget(NextDartStreamView(
      source: source,
      route: '/',
      renderer: _SlotTextRenderer(),
    ));

    // Initial frame: tree with slot 'a' showing its fallback.
    controller.add(_treeWithSlot('a').copyData(initialFrameData()));
    await tester.pump(); // flush stream delivery + setState
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('header'), findsOneWidget);

    // Patch frame for slot 'a'.
    controller.add(EnvelopeContent(
      root: const NdNode(type: 'Text', props: {'text': 'resolved!'}),
      data: patchFrameData('a'),
    ));
    await tester.pump(); // flush stream delivery + setState
    await tester.pump();
    expect(find.text('resolved!'), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);

    await controller.close();
    await tester.pump();
  });

  testWidgets('stream view shows loading builder before the initial frame',
      (tester) async {
    final controller = StreamController<EnvelopeContent>();
    final source = _FakeStreamSource(controller.stream);

    await tester.pumpWidget(NextDartStreamView(
      source: source,
      route: '/',
      renderer: _SlotTextRenderer(),
      loadingBuilder: (_) => const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('booting'),
      ),
    ));
    await tester.pump();
    expect(find.text('booting'), findsOneWidget);

    await controller.close();
    await tester.pump();
  });
}

// Convenience for the test: rebuild content with new data.
extension on EnvelopeContent {
  EnvelopeContent copyData(Map<String, Object?> data) =>
      EnvelopeContent(root: root, components: components, data: data);
}

/// Renders a Column/Text/Slot tree to plain widgets so we can assert on text.
class _SlotTextRenderer extends NextDartRenderer {
  @override
  Widget render(BuildContext context, EnvelopeContent content,
      NdActionDispatcher dispatch) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _node(content.root),
    );
  }

  Widget _node(NdNode n) {
    switch (n.type) {
      case 'Text':
        return Text(n.props['text'] as String? ?? '');
      case 'Column':
        return Column(
            mainAxisSize: MainAxisSize.min,
            children: n.children.map(_node).toList());
      case kSlotType:
        return n.children.isEmpty
            ? const SizedBox.shrink()
            : _node(n.children.first);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _FakeStreamSource extends NextDartSource {
  final Stream<EnvelopeContent> _frames;
  _FakeStreamSource(this._frames);

  @override
  Stream<EnvelopeContent> streamPage(String route) => _frames;

  @override
  Future<EnvelopeContent> fetchPage(String route) async =>
      throw UnimplementedError();
  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
          {required String route}) async =>
      throw UnimplementedError();
}
