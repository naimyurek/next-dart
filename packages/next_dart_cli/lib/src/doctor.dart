/// Doctor feature — pure logic, injectable environment.

/// Abstraction over the runtime environment the doctor checks.
/// Inject a real or fake implementation in tests.
abstract class DoctorEnv {
  /// Tools (executables) available on PATH.
  Set<String> get availableTools;

  /// Directory paths that exist in the workspace.
  Set<String> get existingDirs;
}

/// The four canonical next-dart package directories.
const _requiredPackages = [
  'packages/next_dart_server',
  'packages/next_dart_protocol',
  'packages/next_dart_client',
  'packages/next_dart_rfw',
];

/// Result of running the doctor checks against a [DoctorEnv].
class DoctorReport {
  const DoctorReport({
    required this.dartOk,
    required this.flutterOk,
    required this.missingPackages,
  });

  final bool dartOk;
  final bool flutterOk;
  final List<String> missingPackages;

  bool get isHealthy => dartOk && flutterOk && missingPackages.isEmpty;
}

/// Run all doctor checks using [env] as the source of truth.
DoctorReport runDoctor(DoctorEnv env) {
  final dartOk = env.availableTools.contains('dart');
  final flutterOk = env.availableTools.contains('flutter');
  final missingPackages = _requiredPackages
      .where((p) => !env.existingDirs.contains(p))
      .toList();

  return DoctorReport(
    dartOk: dartOk,
    flutterOk: flutterOk,
    missingPackages: missingPackages,
  );
}
