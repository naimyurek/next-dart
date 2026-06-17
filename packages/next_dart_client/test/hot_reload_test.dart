// packages/next_dart_client/test/hot_reload_test.dart
//
// TDD: RED phase — tests for F6 dev hot-reload on the Flutter client side.
// These tests are written BEFORE any implementation.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_dart_protocol/next_dart_protocol.dart';
import 'package:next_dart_client/src/renderer.dart';
import 'package:next_dart_client/src/source.dart';
import 'package:next_dart_client/src/view.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// A renderer that displays the 'text' prop of the root node.
class _TextRenderer extends NextDartRenderer {
  @override
  Widget render(BuildContext context, EnvelopeContent content,
      NdActionDispatcher dispatch) {
    final label = content.root.props['text'] as String? ?? '';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(label),
    );
  }
}

/// A controllable fake source that allows pushing events via [eventController].
class _FakeSource extends NextDartSource {
  int fetchCallCount = 0;
  int _generation = 0;
  final StreamController<String> eventController =
      StreamController<String>.broadcast();

  @override
  Future<EnvelopeContent> fetchPage(String route) async {
    fetchCallCount++;
    final gen = _generation;
    return EnvelopeContent(
      root: NdNode(type: 'Text', props: {'text': 'gen-$gen'}),
    );
  }

  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route}) async {
    return fetchPage(route);
  }

  @override
  Stream<String> events() => eventController.stream;

  void pushEvent(String event) => eventController.add(event);

  void bumpGeneration() => _generation++;
}

/// A fake source that does NOT override events() — so the default applies.
class _MinimalFakeSource extends NextDartSource {
  int fetchCallCount = 0;

  @override
  Future<EnvelopeContent> fetchPage(String route) async {
    fetchCallCount++;
    return EnvelopeContent(
      root: NdNode(type: 'Text', props: {'text': 'v-$fetchCallCount'}),
    );
  }

  @override
  Future<EnvelopeContent> dispatch(String action, Map<String, Object?> args,
      {required String route}) async {
    return fetchPage(route);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NextDartView hotReload: false (default)', () {
    testWidgets('does not re-fetch when a reload event is emitted',
        (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(NextDartView(
        source: source,
        route: '/',
        renderer: _TextRenderer(),
        // hotReload defaults to false — explicitly omitted to test default
      ));
      await tester.pumpAndSettle();
      expect(find.text('gen-0'), findsOneWidget);

      final countBefore = source.fetchCallCount;

      // Change generation so that a new fetch would produce different output,
      // then fire an event — the view must NOT react.
      source.bumpGeneration();
      source.pushEvent('reload');
      await tester.pumpAndSettle();

      // Still shows stale content; fetchCallCount unchanged.
      expect(find.text('gen-0'), findsOneWidget);
      expect(source.fetchCallCount, countBefore);
    });
  });

  group('NextDartView hotReload: true', () {
    testWidgets(
        'calls fetchPage again and re-renders when a reload event is received',
        (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(NextDartView(
        source: source,
        route: '/',
        renderer: _TextRenderer(),
        hotReload: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('gen-0'), findsOneWidget);

      final countBefore = source.fetchCallCount;

      // Bump generation so next fetch yields different content, then reload.
      source.bumpGeneration();
      source.pushEvent('reload');
      await tester.pumpAndSettle();

      expect(source.fetchCallCount, greaterThan(countBefore));
      expect(find.text('gen-1'), findsOneWidget);
    });

    testWidgets('ignores non-reload events (does not refetch)', (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(NextDartView(
        source: source,
        route: '/',
        renderer: _TextRenderer(),
        hotReload: true,
      ));
      await tester.pumpAndSettle();
      final countBefore = source.fetchCallCount;

      source.pushEvent('some-other-event');
      await tester.pumpAndSettle();

      expect(source.fetchCallCount, countBefore);
    });

    testWidgets('cancels subscription on dispose — no setState after unmount',
        (tester) async {
      final source = _FakeSource();
      await tester.pumpWidget(NextDartView(
        source: source,
        route: '/',
        renderer: _TextRenderer(),
        hotReload: true,
      ));
      await tester.pumpAndSettle();

      // Unmount the widget.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Sending a reload after unmount must not cause exceptions.
      source.bumpGeneration();
      source.pushEvent('reload');
      await tester.pumpAndSettle();
      // No crash = subscription correctly cancelled.
    });
  });

  group('NextDartSource.events() default', () {
    test('default implementation returns Stream.empty()', () async {
      final source = _MinimalFakeSource();
      // events() on the base class must return a stream (not throw).
      final stream = source.events();
      // Collecting it should complete without emitting anything.
      final events = await stream.toList();
      expect(events, isEmpty);
    });
  });
}
