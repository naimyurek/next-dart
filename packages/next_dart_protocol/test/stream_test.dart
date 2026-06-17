import 'package:next_dart_protocol/src/stream.dart';
import 'package:test/test.dart';

void main() {
  group('frame data helpers', () {
    test('constants have the documented wire values', () {
      expect(kSlotType, 'Slot');
      expect(kFrameKind, 'kind');
      expect(kFrameInitial, 'initial');
      expect(kFramePatch, 'patch');
      expect(kFrameSlot, 'slot');
    });

    test('initialFrameData carries kind=initial and no slot', () {
      final data = initialFrameData();
      expect(frameKind(data), kFrameInitial);
      expect(frameSlot(data), isNull);
    });

    test('patchFrameData carries kind=patch and the slot id', () {
      final data = patchFrameData('a');
      expect(frameKind(data), kFramePatch);
      expect(frameSlot(data), 'a');
    });

    test('patchFrameData round-trips an arbitrary slot id', () {
      final data = patchFrameData('hero-section_2');
      expect(frameKind(data), kFramePatch);
      expect(frameSlot(data), 'hero-section_2');
    });

    test('frameKind / frameSlot return null on an unrelated map', () {
      expect(frameKind(const {}), isNull);
      expect(frameSlot(const {}), isNull);
      expect(frameKind(const {'kind': 42}), isNull,
          reason: 'non-string kind is not a valid frame kind');
      expect(frameSlot(const {'slot': 42}), isNull,
          reason: 'non-string slot is not a valid frame slot');
    });
  });
}
