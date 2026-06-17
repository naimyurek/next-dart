import 'dart:io';
import 'package:args/command_runner.dart';
import '../doctor.dart';

/// Real [DoctorEnv] that queries the actual system.
class _SystemEnv implements DoctorEnv {
  @override
  Set<String> get availableTools {
    final found = <String>{};
    for (final tool in ['dart', 'flutter']) {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [tool],
      );
      if (result.exitCode == 0) found.add(tool);
    }
    return found;
  }

  @override
  Set<String> get existingDirs {
    return {
      'packages/next_dart_server',
      'packages/next_dart_protocol',
      'packages/next_dart_client',
      'packages/next_dart_rfw',
    }.where((p) => Directory(p).existsSync()).toSet();
  }
}

class DoctorCommand extends Command<int> {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check that dart, flutter and next-dart packages are available.';

  @override
  Future<int> run() async {
    final report = runDoctor(_SystemEnv());

    _printStatus('dart', report.dartOk);
    _printStatus('flutter', report.flutterOk);

    if (report.missingPackages.isEmpty) {
      stdout.writeln('[ok] All next-dart packages found.');
    } else {
      for (final pkg in report.missingPackages) {
        stdout.writeln('[!!] Missing package directory: $pkg');
      }
    }

    if (report.isHealthy) {
      stdout.writeln('\nAll checks passed.');
      return 0;
    } else {
      stdout.writeln('\nSome checks failed. See above for details.');
      return 1;
    }
  }

  void _printStatus(String tool, bool ok) {
    final mark = ok ? '[ok]' : '[!!]';
    final msg = ok ? '$tool found on PATH.' : '$tool NOT found on PATH.';
    stdout.writeln('$mark $msg');
  }
}
