import 'package:next_dart_cli/next_dart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('buildRunner', () {
    test('unknown command exits with usage error (non-zero)', () async {
      final runner = buildRunner();
      Object? caught;
      try {
        await runner.run(['unknown-cmd-xyz']);
      } catch (e) {
        caught = e;
      }
      // args package throws UsageException for unknown commands
      expect(caught, isNotNull);
    });

    test('--help lists new, dev, and doctor commands', () async {
      final runner = buildRunner();
      final output = runner.usage;
      expect(output, contains('new'));
      expect(output, contains('dev'));
      expect(output, contains('doctor'));
    });
  });
}
