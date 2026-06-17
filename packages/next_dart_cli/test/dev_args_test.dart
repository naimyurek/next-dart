import 'package:next_dart_cli/next_dart_cli.dart';
import 'package:test/test.dart';

void main() {
  group('devProcessArgs', () {
    test('returns run, define PORT, and bin/server.dart', () {
      final args = devProcessArgs(dir: '.', port: 8080);
      expect(args, equals(['run', '--define=PORT=8080', 'bin/server.dart']));
    });

    test('embeds the port number in the define flag', () {
      final args = devProcessArgs(dir: '.', port: 9000);
      expect(args, contains('--define=PORT=9000'));
    });

    test('always starts with run', () {
      final args = devProcessArgs(dir: '.', port: 3000);
      expect(args.first, equals('run'));
    });

    test('always ends with bin/server.dart', () {
      final args = devProcessArgs(dir: '.', port: 4000);
      expect(args.last, equals('bin/server.dart'));
    });
  });
}
