import 'package:args/command_runner.dart';
import 'commands/dev_command.dart';
import 'commands/doctor_command.dart';
import 'commands/new_command.dart';

/// Build and return the [CommandRunner] with all next_dart_cli commands registered.
CommandRunner<int> buildRunner() {
  final runner = CommandRunner<int>(
    'next_dart',
    'The next-dart CLI — scaffold and run server-driven Flutter apps.',
  )
    ..addCommand(NewCommand())
    ..addCommand(DevCommand())
    ..addCommand(DoctorCommand());

  return runner;
}
