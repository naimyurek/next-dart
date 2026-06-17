import 'dart:io';
import 'package:args/command_runner.dart';
import '../scaffold.dart';

class NewCommand extends Command<int> {
  NewCommand() {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Directory in which to create the project.',
    );
  }

  @override
  String get name => 'new';

  @override
  String get description => 'Scaffold a new next-dart project.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('A project name is required.');
    }
    final projectName = rest.first;
    final outputDir = argResults!.option('output') ?? projectName;

    final files = generateScaffold(projectName);

    for (final entry in files.entries) {
      final file = File('$outputDir/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }

    stdout.writeln('Created $projectName in $outputDir');
    return 0;
  }
}
