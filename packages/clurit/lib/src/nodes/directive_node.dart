import 'node.dart';

/// A generic directive node for custom @directive(...) calls.
class DirectiveNode extends Node {
  final String name;
  final List<String> args;
  final String Function(String name, List<String> args, Map<String, dynamic> context) handler;

  DirectiveNode({
    required this.name,
    required this.args,
    required this.handler,
  });

  @override
  String compile(Map<String, dynamic> context) {
    return handler(name, args, context);
  }
}
