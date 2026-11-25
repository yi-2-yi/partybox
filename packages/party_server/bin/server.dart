import 'dart:io';

import 'package:party_server/party_server.dart';

Future<void> main(List<String> args) async {
  final portEnv = Platform.environment['PORT'];
  final port = int.tryParse(portEnv ?? '') ?? 8080;

  final server = PartyServer();
  await server.start(address: InternetAddress.anyIPv4, port: port);

  stdout.writeln('PartyBox Online Server running on ws://0.0.0.0:${server.port}/ws');
  stdout.writeln('Health check: http://0.0.0.0:${server.port}/health');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nShutting down PartyBox server...');
    await server.stop();
    exit(0);
  });
}
