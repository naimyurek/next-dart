import 'dart:io';
import 'package:next_dart_cli/next_dart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('new command writes files to disk', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('next_dart_new_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates pubspec.yaml', () async {
      final runner = buildRunner();
      await runner.run(['new', 'testproj', '--output', tempDir.path]);
      expect(File('${tempDir.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('creates bin/server.dart', () async {
      final runner = buildRunner();
      await runner.run(['new', 'testproj', '--output', tempDir.path]);
      expect(File('${tempDir.path}/bin/server.dart').existsSync(), isTrue);
    });

    test('creates lib/app.dart', () async {
      final runner = buildRunner();
      await runner.run(['new', 'testproj', '--output', tempDir.path]);
      expect(File('${tempDir.path}/lib/app.dart').existsSync(), isTrue);
    });

    test('creates README.md', () async {
      final runner = buildRunner();
      await runner.run(['new', 'testproj', '--output', tempDir.path]);
      expect(File('${tempDir.path}/README.md').existsSync(), isTrue);
    });

    test('pubspec.yaml contains the project name', () async {
      final runner = buildRunner();
      await runner.run(['new', 'testproj', '--output', tempDir.path]);
      final content = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(content, contains('name: testproj'));
    });
  });
}
