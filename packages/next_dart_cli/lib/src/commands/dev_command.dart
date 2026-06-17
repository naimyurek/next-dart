import 'dart:io';
import 'package:args/command_runner.dart';
import '../dev_args.dart';

class DevCommand extends Command<int> {
  DevCommand() {
    argParser
      ..addOption(
        'dir',
        abbr: 'd',
        defaultsTo: '.',
        help: 'Directory containing the server package.',
      )
      ..addOption(
        'port',
        abbr: 'p',
        defaultsTo: '8080',
        help: 'Port for the dev server.',
      );
  }

  @override
  String get name => 'dev';

  @override
  String get description => 'Start the next-dart dev server.';

  @override
  Future<int> run() async {
    final dir = argResults!.option('dir')!;
    final portStr = argResults!.option('port')!;
    final port = int.tryParse(portStr);
    if (port == null) {
      usageException('--port must be an integer, got: $portStr');
    }

    final args = devProcessArgs(dir: dir, port: port);
    stdout.writeln('Starting: dart ${args.join(' ')} (in $dir)');

    final process = await Process.start(
      'dart',
      args,
      workingDirectory: dir,
      mode: ProcessStartMode.inheritStdio,
    );

    return process.exitCode;
  }
}
