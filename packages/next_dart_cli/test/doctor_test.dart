import 'package:next_dart_cli/next_dart_cli.dart';
import 'package:test/test.dart';

/// A fake [DoctorEnv] that uses provided sets to drive checks.
class FakeEnv implements DoctorEnv {
  FakeEnv({
    required this.availableTools,
    required this.existingDirs,
  });

  @override
  final Set<String> availableTools;

  @override
  final Set<String> existingDirs;
}

void main() {
  group('runDoctor', () {
    final allPackages = {
      'packages/next_dart_server',
      'packages/next_dart_protocol',
      'packages/next_dart_client',
      'packages/next_dart_rfw',
    };

    test('all-ok when dart, flutter and all packages present', () {
      final env = FakeEnv(
        availableTools: {'dart', 'flutter'},
        existingDirs: allPackages,
      );
      final report = runDoctor(env);
      expect(report.dartOk, isTrue);
      expect(report.flutterOk, isTrue);
      expect(report.missingPackages, isEmpty);
      expect(report.isHealthy, isTrue);
    });

    test('dartOk is false when dart is missing from PATH', () {
      final env = FakeEnv(
        availableTools: {'flutter'},
        existingDirs: allPackages,
      );
      final report = runDoctor(env);
      expect(report.dartOk, isFalse);
      expect(report.isHealthy, isFalse);
    });

    test('flutterOk is false when flutter is missing from PATH', () {
      final env = FakeEnv(
        availableTools: {'dart'},
        existingDirs: allPackages,
      );
      final report = runDoctor(env);
      expect(report.flutterOk, isFalse);
      expect(report.isHealthy, isFalse);
    });

    test('missingPackages lists absent directories', () {
      final env = FakeEnv(
        availableTools: {'dart', 'flutter'},
        existingDirs: {
          'packages/next_dart_server',
          'packages/next_dart_protocol',
          // missing: next_dart_client, next_dart_rfw
        },
      );
      final report = runDoctor(env);
      expect(report.missingPackages, containsAll([
        'packages/next_dart_client',
        'packages/next_dart_rfw',
      ]));
      expect(report.isHealthy, isFalse);
    });

    test('isHealthy is false when both tools missing', () {
      final env = FakeEnv(
        availableTools: const {},
        existingDirs: allPackages,
      );
      final report = runDoctor(env);
      expect(report.isHealthy, isFalse);
    });
  });
}
