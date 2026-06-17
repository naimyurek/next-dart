// packages/next_dart_server/test/events_test.dart
//
// TDD: RED phase — tests for F6 dev hot-reload SSE endpoint.
// These tests are written BEFORE any implementation.
import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:next_dart_server/next_dart_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late SimpleKeyPair signingKp;
  final secret = SecretKey(List.filled(32, 7));

  setUp(() async {
    signingKp = await Ed25519().newKeyPair();
  });

  NextDartApp buildApp({bool devMode = false}) {
    final app = NextDartApp(
      signingKeyPair: signingKp,
      secretKey: secret,
      keyId: 'k1',
      devMode: devMode,
    );
    app.page('/', (ctx) => ndText('hello'));
    return app;
  }

  group('devMode: false (default)', () {
    test('GET /__events returns 404 when devMode is false', () async {
      final handler = buildApp(devMode: false).handler;
      final res = await handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 404);
    });

    test('GET /__events returns 404 when devMode defaults to false', () async {
      final app = NextDartApp(
        signingKeyPair: signingKp,
        secretKey: secret,
        keyId: 'k1',
      );
      app.page('/', (ctx) => ndText('hi'));
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 404);
    });
  });

  group('devMode: true', () {
    test('GET /__events returns 200 with content-type: text/event-stream',
        () async {
      final app = buildApp(devMode: true);
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/event-stream'));
    });

    test('GET /__events emits initial ": connected" SSE comment', () async {
      final app = buildApp(devMode: true);
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 200);

      // Read first chunk with a timeout — the comment should arrive immediately.
      final chunks = res.read();
      final firstChunk = await chunks.first
          .timeout(const Duration(seconds: 2), onTimeout: () => <int>[]);
      final firstText = utf8.decode(firstChunk);
      expect(firstText, contains(': connected'));
    });

    test(
        'bumpContent() causes "data: reload" frame to be emitted on the SSE stream',
        () async {
      final app = buildApp(devMode: true);
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 200);

      // Collect SSE frames in a list. We'll cancel after we see a reload.
      final received = <String>[];
      final completer = Completer<void>();
      final sub = res.read().transform(utf8.decoder).listen((chunk) {
        received.add(chunk);
        if (chunk.contains('data: reload') && !completer.isCompleted) {
          completer.complete();
        }
      });

      // Trigger a reload event after the stream is set up.
      await Future<void>.delayed(Duration.zero);
      app.bumpContent();

      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('no reload frame received within 2s'),
      );
      await sub.cancel();

      final combined = received.join();
      expect(combined, contains('data: reload'));
    });

    test('multiple bumpContent() calls each emit a reload frame', () async {
      final app = buildApp(devMode: true);
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__events')),
      );
      expect(res.statusCode, 200);

      final received = <String>[];
      int reloadCount = 0;
      final completer = Completer<void>();

      final sub = res.read().transform(utf8.decoder).listen((chunk) {
        received.add(chunk);
        if (chunk.contains('data: reload')) {
          reloadCount++;
          if (reloadCount >= 2 && !completer.isCompleted) {
            completer.complete();
          }
        }
      });

      await Future<void>.delayed(Duration.zero);
      app.bumpContent();
      app.bumpContent();

      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () =>
            throw TimeoutException('did not receive 2 reload frames within 2s'),
      );
      await sub.cancel();

      expect(reloadCount, greaterThanOrEqualTo(2));
    });

    test('existing routes still work when devMode is true', () async {
      final app = buildApp(devMode: true);
      final res = await app.handler(
        Request('GET', Uri.parse('http://x/__page?route=/')),
      );
      expect(res.statusCode, 200);
    });
  });
}
