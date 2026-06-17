// packages/next_dart_protocol/test/binary_codec_test.dart
import 'dart:convert';

import 'package:next_dart_protocol/src/binary_codec.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:next_dart_protocol/src/envelope_body.dart';
import 'package:next_dart_protocol/src/node.dart';
import 'package:test/test.dart';

/// A representative body used across multiple tests.
EnvelopeBody sampleBody() => EnvelopeBody(
      root: NdNode(
        type: 'Column',
        props: {},
        children: [
          NdNode(
            type: 'Text',
            props: {'text': 'hello', 'size': 14, 'ratio': 1.5, 'bold': true},
            children: [],
            events: {},
          ),
          NdNode(
            type: 'Button',
            props: {'label': NdArgRef('btnLabel')},
            children: [],
            events: {
              'onTap': NdActionRef('navigate', {'route': '/home', 'count': 42}),
            },
          ),
        ],
        events: {},
      ),
      components: [
        NdComponentDef(
          name: 'Card',
          params: ['title', 'subtitle'],
          body: NdNode(
            type: 'Column',
            props: {},
            children: [
              NdNode(
                type: 'Text',
                props: {'text': NdArgRef('title'), 'size': 18},
                children: [],
                events: {},
              ),
              NdNode(
                type: 'Text',
                props: {'text': NdArgRef('subtitle')},
                children: [],
                events: {},
              ),
            ],
            events: {},
          ),
        ),
      ],
      data: {'theme': 'dark', 'version': 2, 'flag': true},
    );

void main() {
  group('binary round-trip', () {
    test('decodeTreeBinary(encodeTreeBinary(x)) is structurally equal to x',
        () {
      final body = sampleBody();
      final encoded = encodeTreeBinary(body);
      final decoded = decodeTreeBinary(encoded);

      // Compare via toJson() as specified in the design.
      expect(decoded.root.toJson(), equals(body.root.toJson()));
      expect(
        decoded.components.map((c) => c.toJson()).toList(),
        equals(body.components.map((c) => c.toJson()).toList()),
      );
      expect(decoded.data, equals(body.data));
    });

    test('null prop value round-trips', () {
      final body = EnvelopeBody(
        root: NdNode(type: 'Box', props: {'x': null}, children: [], events: {}),
        components: [],
        data: {},
      );
      final decoded = decodeTreeBinary(encodeTreeBinary(body));
      expect(decoded.root.props['x'], isNull);
      expect(decoded.root.props.containsKey('x'), isTrue);
    });

    test('deeply nested nodes round-trip', () {
      NdNode nest(int depth) {
        if (depth == 0) return NdNode(type: 'Leaf', props: {'d': depth});
        return NdNode(type: 'Wrap', children: [nest(depth - 1)]);
      }

      final body = EnvelopeBody(root: nest(5), components: [], data: {});
      final decoded = decodeTreeBinary(encodeTreeBinary(body));
      expect(decoded.root.toJson(), equals(body.root.toJson()));
    });

    test('empty body round-trips', () {
      final body = EnvelopeBody(
        root: NdNode(type: 'Empty'),
        components: [],
        data: {},
      );
      final decoded = decodeTreeBinary(encodeTreeBinary(body));
      expect(decoded.root.toJson(), equals(body.root.toJson()));
      expect(decoded.components, isEmpty);
      expect(decoded.data, isEmpty);
    });
  });

  group('size comparison', () {
    test('binary plaintext is smaller than JSON for the sample', () {
      final body = sampleBody();

      final binaryBytes = encodeTreeBinary(body);
      final jsonBytes = utf8.encode(jsonEncode({
        'root': body.root.toJson(),
        'components': body.components.map((c) => c.toJson()).toList(),
        'data': body.data,
      }));

      // Print sizes for the report.
      // ignore: avoid_print
      print('JSON: ${jsonBytes.length} bytes, binary: ${binaryBytes.length} bytes');

      expect(binaryBytes.length, lessThan(jsonBytes.length),
          reason:
              'ndBinary should produce fewer bytes than JSON for a representative tree');
    });
  });
}
