// packages/next_dart_server/test/component_library_test.dart
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  // ── helpers ───────────────────────────────────────────────────────────────

  NdComponentDef makeDef(String name) => NdComponentDef(
        name: name,
        params: [],
        body: NdNode(type: 'Text', props: {'text': name}),
      );

  // ── ComponentLibrary / ComponentRegistry unit tests ───────────────────────

  group('ComponentRegistry', () {
    test('merges components from multiple libraries and stamps library identity',
        () {
      final libA = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Button'), makeDef('Badge')],
      );
      final libB = ComponentLibrary(
        name: 'forms',
        version: '2.3.1',
        components: [makeDef('TextField')],
      );
      final registry = ComponentRegistry(libraries: [libA, libB]);

      final all = registry.all();
      expect(all.length, 3);

      final button = all.firstWhere((d) => d.name == 'Button');
      expect(button.library, 'ui_kit');
      expect(button.libraryVersion, '1.0.0');

      final textField = all.firstWhere((d) => d.name == 'TextField');
      expect(textField.library, 'forms');
      expect(textField.libraryVersion, '2.3.1');
    });

    test('merges flat components (unnamed library) alongside named libraries',
        () {
      final flatDef = makeDef('Chip');
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Button')],
      );
      final registry = ComponentRegistry(
        flatComponents: [flatDef],
        libraries: [lib],
      );

      final all = registry.all();
      expect(all.length, 2);

      // flat component keeps library == null
      final chip = all.firstWhere((d) => d.name == 'Chip');
      expect(chip.library, isNull);
      expect(chip.libraryVersion, isNull);

      // library component gets stamped
      final button = all.firstWhere((d) => d.name == 'Button');
      expect(button.library, 'ui_kit');
    });

    test('duplicate name across libraries throws StateError at construction',
        () {
      final libA = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Button')],
      );
      final libB = ComponentLibrary(
        name: 'legacy',
        version: '0.1.0',
        components: [makeDef('Button')], // same name as libA
      );
      expect(
        () => ComponentRegistry(libraries: [libA, libB]),
        throwsA(isA<StateError>()),
      );
    });

    test('duplicate name between flat components and a library throws StateError',
        () {
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Chip')],
      );
      expect(
        () => ComponentRegistry(flatComponents: [makeDef('Chip')], libraries: [lib]),
        throwsA(isA<StateError>()),
      );
    });

    test('lookup returns the correct component', () {
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Avatar'), makeDef('Badge')],
      );
      final registry = ComponentRegistry(libraries: [lib]);

      final def = registry.lookup('Avatar');
      expect(def, isNotNull);
      expect(def!.library, 'ui_kit');
      expect(def.libraryVersion, '1.0.0');
    });

    test('lookup returns null for unknown component', () {
      final registry = ComponentRegistry();
      expect(registry.lookup('NonExistent'), isNull);
    });

    test('original NdComponentDef instances are not mutated (new instances returned)',
        () {
      final original = makeDef('Card');
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [original],
      );
      ComponentRegistry(libraries: [lib]);
      // The original def must be untouched
      expect(original.library, isNull);
      expect(original.libraryVersion, isNull);
    });
  });

  // ── NextDartApp integration tests ─────────────────────────────────────────

  group('NextDartApp with componentLibraries', () {
    late SimpleKeyPair signingKp;
    late SimplePublicKey signingPub;
    final secret = SecretKey(List.filled(32, 7));

    setUp(() async {
      signingKp = await Ed25519().newKeyPair();
      signingPub = await signingKp.extractPublicKey();
    });

    Future<EnvelopeContent> decodeBody(Response r) async {
      final bytes = await r.read().expand((x) => x).toList();
      return decodeEnvelope(bytes,
          secretKey: secret,
          signingPublicKey: signingPub,
          clientVersion: '1.0.0');
    }

    test(
        'GET /__page envelope includes library-stamped component definitions',
        () async {
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '3.0.0',
        components: [makeDef('Badge'), makeDef('Avatar')],
      );
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
        componentLibraries: [lib],
      );
      app.page('/', (ctx) => NdNode(type: 'Column'));

      final res = await app.handler(
          Request('GET', Uri.parse('http://x/__page?route=/')));
      expect(res.statusCode, 200);

      final content = await decodeBody(res);
      expect(content.components.length, 2);

      final badge = content.components.firstWhere((d) => d.name == 'Badge');
      expect(badge.library, 'ui_kit');
      expect(badge.libraryVersion, '3.0.0');
    });

    test(
        'NextDartApp with duplicate component name across libraries '
        'throws StateError at construction', () async {
      final libA = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Button')],
      );
      final libB = ComponentLibrary(
        name: 'legacy',
        version: '0.1.0',
        components: [makeDef('Button')],
      );
      expect(
        () => NextDartApp(
          signingKeyPair: signingKp,
          secretKey: secret,
          keyId: 'k1',
          componentLibraries: [libA, libB],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('back-compat: components param still works alongside componentLibraries',
        () async {
      final flatDef = makeDef('Chip');
      final lib = ComponentLibrary(
        name: 'ui_kit',
        version: '1.0.0',
        components: [makeDef('Badge')],
      );
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
        components: [flatDef],
        componentLibraries: [lib],
      );
      app.page('/', (ctx) => NdNode(type: 'Column'));

      final res = await app.handler(
          Request('GET', Uri.parse('http://x/__page?route=/')));
      final content = await decodeBody(res);
      expect(content.components.length, 2);

      // flat component has no library stamp
      final chip = content.components.firstWhere((d) => d.name == 'Chip');
      expect(chip.library, isNull);

      // library component is stamped
      final badge = content.components.firstWhere((d) => d.name == 'Badge');
      expect(badge.library, 'ui_kit');
    });
  });
}
