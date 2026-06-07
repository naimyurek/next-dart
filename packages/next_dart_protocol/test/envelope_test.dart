import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/src/node.dart';
import 'package:next_dart_protocol/src/component.dart';
import 'package:next_dart_protocol/src/envelope.dart';
import 'package:next_dart_protocol/src/errors.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 3));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  EnvelopeContent sample() => EnvelopeContent(
        root: NdNode(type: 'Text', props: {'text': 'hi'}),
        components: [
          NdComponentDef(
              name: 'C', params: ['x'], body: NdNode(type: 'Text', props: {'text': NdArgRef('x')})),
        ],
        data: const {},
      );

  test('encode then decode returns equivalent content', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '1.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    final out = await decodeEnvelope(
      wire,
      secretKey: secret,
      signingPublicKey: signingPub,
      clientVersion: '1.0.0',
    );
    expect(out.root.props['text'], 'hi');
    expect(out.components.single.name, 'C');
  });

  test('tampered ciphertext fails signature verification', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '1.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    final map = jsonDecode(utf8.decode(wire)) as Map<String, Object?>;
    map['cipherText'] = base64.encode([0, 0, 0, 0]); // tamper
    final tampered = utf8.encode(jsonEncode(map));
    expect(
      () => decodeEnvelope(tampered,
          secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0'),
      throwsA(isA<SignatureError>()),
    );
  });

  test('wrong signing key causes SignatureError', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '1.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    // Generate a different keypair and use its public key for verification.
    final otherKp = await Ed25519().newKeyPair();
    final otherPub = await otherKp.extractPublicKey();
    expect(
      () => decodeEnvelope(wire,
          secretKey: secret, signingPublicKey: otherPub, clientVersion: '1.0.0'),
      throwsA(isA<SignatureError>()),
    );
  });

  test('client older than minClientVersion is rejected', () async {
    final wire = await encodeEnvelope(
      content: sample(),
      route: '/',
      contentVersion: 1,
      minClientVersion: '2.0.0',
      keyId: 'k1',
      secretKey: secret,
      signingKeyPair: signingKp,
    );
    expect(
      () => decodeEnvelope(wire,
          secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0'),
      throwsA(isA<UpdateRequiredError>()),
    );
  });
}
