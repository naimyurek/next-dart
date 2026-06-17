import 'package:next_dart_cli/next_dart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('generateScaffold', () {
    late Map<String, String> files;

    setUpAll(() {
      files = generateScaffold('myapp');
    });

    test('returns pubspec.yaml', () {
      expect(files.containsKey('pubspec.yaml'), isTrue);
    });

    test('returns bin/server.dart', () {
      expect(files.containsKey('bin/server.dart'), isTrue);
    });

    test('returns lib/app.dart', () {
      expect(files.containsKey('lib/app.dart'), isTrue);
    });

    test('returns README.md', () {
      expect(files.containsKey('README.md'), isTrue);
    });

    test('pubspec.yaml contains the project name', () {
      expect(files['pubspec.yaml'], contains('name: myapp'));
    });

    test('bin/server.dart references NextDartApp', () {
      expect(files['bin/server.dart'], contains('NextDartApp'));
    });

    test('bin/server.dart references serve / shelf_io', () {
      expect(files['bin/server.dart'], contains('shelf_io'));
    });

    test('lib/app.dart defines buildApp function', () {
      expect(files['lib/app.dart'], contains('buildApp'));
    });

    test('bin/server.dart uses NextDartApp.dev (not .insecure)', () {
      final server = files['bin/server.dart']!;
      expect(server, contains('NextDartApp.dev'));
      expect(server, isNot(contains('.insecure')));
    });

    test('lib/app.dart uses NextDartApp.dev (not .insecure)', () {
      final app = files['lib/app.dart']!;
      expect(app, contains('NextDartApp.dev'));
      expect(app, isNot(contains('.insecure')));
    });

    test('README.md mentions the project name', () {
      expect(files['README.md'], contains('myapp'));
    });

    test('returns exactly four entries', () {
      expect(files.length, equals(4));
    });
  });
}
