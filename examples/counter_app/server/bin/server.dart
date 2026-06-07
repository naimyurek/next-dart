// examples/counter_app/server/bin/server.dart
import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:counter_server/app.dart';

Future<void> main() async {
  final app = await buildApp();
  // Use loopbackIPv4 (127.0.0.1) for local development; change to anyIPv4
  // (0.0.0.0) when deploying or when your OS/firewall allows binding to all interfaces.
  final port = int.tryParse(const String.fromEnvironment('PORT', defaultValue: '8080')) ?? 8080;
  final server =
      await shelf_io.serve(app.handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln(
      'next-dart demo on http://${server.address.host}:${server.port}');
}
