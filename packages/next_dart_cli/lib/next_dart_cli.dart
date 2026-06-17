/// next_dart_cli — public API.
///
/// Exports the CommandRunner factory and all pure testable helpers.
library next_dart_cli;

export 'src/runner.dart' show buildRunner;
export 'src/scaffold.dart' show generateScaffold;
export 'src/dev_args.dart' show devProcessArgs;
export 'src/doctor.dart' show DoctorEnv, DoctorReport, runDoctor;
