// packages/next_dart_protocol/test/envelope_binary_test.dart
//
// Tests for the ndBinary format path in encodeEnvelope / decodeEnvelope.
// The existing envelope_test.dart (JSON path) is untouched.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/canonical.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:next_dart_protocol/src/crypto.dart';
import 'package:next_dart_protocol/src/envelope.dart';
import 'package:next_dart_protocol/src/errors.dart';
import 'package:next_dart_protocol/src/node.dart';
import 'package:test/test.dart';

EnvelopeContent richSample() => EnvelopeContent(
      root: NdNode(
        type: 'Column',
        props: {},
        children: [
          NdNode(
            type: 'Text',
            props: {
              'text': 'hello',
              'size': 14,
              'ratio': 1.5,
              'bold': true,
              'tag': null,
            },
          ),
          NdNode(
            type: 'Button',
            props: {'label': NdArgRef('btnLabel')},
            events: {
              'onTap': NdActionRef('navigate', {'route': '/home', 'count': 42}),
            },
          ),
        ],
      ),
      components: [
        NdComponentDef(
          name: 'Card',
          params: ['title', 'subtitle'],
          body: NdNode(
            type: 'Column',
            children: [
              NdNode(type: 'Text', props: {'text': NdArgRef('title')}),
              NdNode(type: 'Text', props: {'text': NdArgRef('subtitle')}),
            ],
          ),
        ),
      ],
      data: {'theme': 'dark', 'version': 2},
    );

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 7));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  group('ndBinary envelope', () {
    test(
        'encodeEnvelope(ndBinary) then decodeEnvelope returns equivalent content',
        () async {
      final content = richSample();
      final wire = await encodeEnvelope(
        content: content,
        route: '/test',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        format: NdPayloadFormat.ndBinary,
      );
      final out = await decodeEnvelope(
        wire,
        secretKey: secret,
        signingPublicKey: signingPub,
        clientVersion: '1.0.0',
      );

      expect(out.root.toJson(), equals(content.root.toJson()));
      expect(
        out.components.map((c) => c.toJson()).toList(),
        equals(content.components.map((c) => c.toJson()).toList()),
      );
      expect(out.data, equals(content.data));
    });

    test('ndBinary wire carries payloadFormat=ndBinary in header', () async {
      final wire = await encodeEnvelope(
        content: richSample(),
        route: '/test',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        format: NdPayloadFormat.ndBinary,
      );
      final map = jsonDecode(utf8.decode(wire)) as Map<String, Object?>;
      expect(map['payloadFormat'], 'ndBinary');
    });

    test('ndBinary ciphertext is smaller than JSON ciphertext for the sample',
        () async {
      final content = richSample();

      final binaryWire = await encodeEnvelope(
        content: content,
        route: '/test',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        format: NdPayloadFormat.ndBinary,
      );
      final jsonWire = await encodeEnvelope(
        content: content,
        route: '/test',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        // default: json
      );

      // AES-GCM ciphertext length == plaintext length, so a shorter binary
      // plaintext → shorter cipherText field.
      final binaryMap = jsonDecode(utf8.decode(binaryWire)) as Map;
      final jsonMap = jsonDecode(utf8.decode(jsonWire)) as Map;
      final binaryCtLen =
          base64.decode(binaryMap['cipherText'] as String).length;
      final jsonCtLen = base64.decode(jsonMap['cipherText'] as String).length;

      // ignore: avoid_print
      print(
          'Ciphertext lengths — JSON: $jsonCtLen bytes, ndBinary: $binaryCtLen bytes');
      expect(binaryCtLen, lessThan(jsonCtLen),
          reason:
              'ndBinary ciphertext must be smaller than JSON ciphertext for a representative tree');
    });

    test('default format is json (back-compat)', () async {
      final wire = await encodeEnvelope(
        content: richSample(),
        route: '/',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        // no format parameter
      );
      final map = jsonDecode(utf8.decode(wire)) as Map<String, Object?>;
      expect(map['payloadFormat'], 'json');
    });

    test('unknown payloadFormat in a validly-signed envelope causes DecodeError',
        () async {
      // Start from a valid ndBinary wire envelope, strip the signature, tamper
      // payloadFormat, then re-sign using the same key pair so the sig check
      // passes — only the dispatch on payloadFormat should fail.
      final validWire = await encodeEnvelope(
        content: richSample(),
        route: '/',
        contentVersion: 1,
        minClientVersion: '1.0.0',
        keyId: 'k1',
        secretKey: secret,
        signingKeyPair: signingKp,
        format: NdPayloadFormat.ndBinary,
      );

      final full =
          (jsonDecode(utf8.decode(validWire)) as Map).cast<String, Object?>();
      // Build header (no signature) with tampered format.
      final header = Map<String, Object?>.from(full)..remove('signature');
      header['payloadFormat'] = 'superBinary'; // unknown

      // Re-sign so the signature is valid over the tampered header.
      final sigBytes =
          await NdSigner().sign(canonicalJsonBytes(header), signingKp);
      final tamperedWire = utf8.encode(
          jsonEncode({...header, 'signature': base64.encode(sigBytes)}));

      await expectLater(
        decodeEnvelope(
          tamperedWire,
          secretKey: secret,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0',
        ),
        throwsA(isA<DecodeError>()),
      );
    });
  });
}
