import 'dart:io';
import 'package:next_dart_cli/next_dart_cli.dart';

Future<void> main(List<String> arguments) async {
  final runner = buildRunner();
  try {
    final exitCode = await runner.run(arguments) ?? 0;
    exit(exitCode);
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  }
}
