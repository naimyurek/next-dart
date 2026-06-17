import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  late SimplePublicKey signingPub;
  final secret = SecretKey(List.filled(32, 7));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
    signingPub = await signingKp.extractPublicKey();
  });

  NextDartApp buildApp() {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
    );
    // Page with one slot 'a' that initially shows a Loading fallback.
    app.page('/', (ctx) {
      return ndColumn([
        ndText('header'),
        ndSlot('a', fallback: ndText('Loading…')),
      ]);
    });
    // The async work that resolves slot 'a'.
    app.slotResolver('/', 'a', () async => ndText('resolved-a'));
    return app;
  }

  Future<EnvelopeContent> decodeFrame(String base64Line) {
    final bytes = base64.decode(base64Line);
    return decodeEnvelope(bytes,
        secretKey: secret, signingPublicKey: signingPub, clientVersion: '1.0.0');
  }

  test('app.stream emits an initial frame then a patch frame per slot', () async {
    final app = buildApp();
    final chunks = await app
        .stream('/', sessionKey: secret, sessionKeyId: 'k1')
        .toList();
    // Join all bytes then split into base64 lines (impl may chunk however).
    final body = chunks.map(utf8.decode).join();
    final lines = const LineSplitter()
        .convert(body)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines.length, 2, reason: 'one initial + one patch');

    // Frame 0: initial — tree contains a Slot with id 'a'.
    final initial = await decodeFrame(lines[0]);
    expect(frameKind(initial.data), kFrameInitial);
    expect(frameSlot(initial.data), isNull);
    final slotNode = initial.root.children
        .firstWhere((n) => n.type == kSlotType, orElse: () => initial.root);
    expect(slotNode.type, kSlotType);
    expect(slotNode.props['slot'], 'a');
    // Fallback is carried as the slot's child.
    expect(slotNode.children.single.props['text'], 'Loading…');

    // Frame 1: patch — kind patch, slot 'a', root is the resolved Text.
    final patch = await decodeFrame(lines[1]);
    expect(frameKind(patch.data), kFramePatch);
    expect(frameSlot(patch.data), 'a');
    expect(patch.root.props['text'], 'resolved-a');
  });

  test('GET /__stream returns newline-delimited base64 frame lines', () async {
    final app = buildApp();
    final res = await app.handler(
        Request('GET', Uri.parse('http://x/__stream?route=/')));
    expect(res.statusCode, 200);
    expect(res.headers['content-type'], contains('text/plain'));
    final body = await res.readAsString();
    final lines = const LineSplitter()
        .convert(body)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines.length, 2);

    final initial = await decodeFrame(lines[0]);
    expect(frameKind(initial.data), kFrameInitial);
    final patch = await decodeFrame(lines[1]);
    expect(frameKind(patch.data), kFramePatch);
    expect(patch.root.props['text'], 'resolved-a');
  });

  test('GET /__stream with no slots emits only the initial frame', () async {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
    );
    app.page('/plain', (ctx) => ndColumn([ndText('static')]));
    final res = await app.handler(
        Request('GET', Uri.parse('http://x/__stream?route=/plain')));
    expect(res.statusCode, 200);
    final body = await res.readAsString();
    final lines = const LineSplitter()
        .convert(body)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines.length, 1);
    final initial = await decodeFrame(lines.single);
    expect(frameKind(initial.data), kFrameInitial);
  });

  test('GET /__stream on an unknown route returns 404', () async {
    final app = buildApp();
    final res = await app.handler(
        Request('GET', Uri.parse('http://x/__stream?route=/nope')));
    expect(res.statusCode, 404);
  });

  test('multiple slot resolvers each produce a patch frame in order', () async {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
    );
    app.page('/multi', (ctx) => ndColumn([
          ndSlot('a', fallback: ndText('la')),
          ndSlot('b', fallback: ndText('lb')),
        ]));
    app.slotResolver('/multi', 'a', () async => ndText('ra'));
    app.slotResolver('/multi', 'b', () async => ndText('rb'));

    final res = await app.handler(
        Request('GET', Uri.parse('http://x/__stream?route=/multi')));
    final body = await res.readAsString();
    final lines = const LineSplitter()
        .convert(body)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines.length, 3, reason: 'initial + 2 patches');

    final patchA = await decodeFrame(lines[1]);
    final patchB = await decodeFrame(lines[2]);
    expect(frameSlot(patchA.data), 'a');
    expect(patchA.root.props['text'], 'ra');
    expect(frameSlot(patchB.data), 'b');
    expect(patchB.root.props['text'], 'rb');
  });

  test('ndSlot builds the documented Slot node shape', () {
    final node = ndSlot('x', fallback: ndText('f'));
    expect(node.type, kSlotType);
    expect(node.props['slot'], 'x');
    expect(node.children.single.props['text'], 'f');
  });
}
