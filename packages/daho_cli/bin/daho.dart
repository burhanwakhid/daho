import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:daho_cli/src/commands/auth_command.dart';
import 'package:daho_cli/src/commands/build_command.dart';
import 'package:daho_cli/src/commands/create_command.dart';
import 'package:daho_cli/src/commands/doctor_command.dart';
import 'package:daho_cli/src/commands/run_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('daho', 'CLI for the Daho HTTP framework.')
    ..addCommand(CreateCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(BuildCommand())
    ..addCommand(RunCommand())
    ..addCommand(AuthCommand());

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}
