import 'node.dart';

/// A node for @include directive — includes another template.
class IncludeNode extends Node {
  final String template;
  final Map<String, dynamic>? data;
  final Node Function(String template, Map<String, dynamic>? data) resolver;

  IncludeNode({
    required this.template,
    this.data,
    required this.resolver,
  });

  @override
  String compile(Map<String, dynamic> context) {
    final mergedContext = Map<String, dynamic>.from(context);
    if (data != null) {
      mergedContext.addAll(data!);
    }
    final resolved = resolver(template, mergedContext);
    return resolved.compile(mergedContext);
  }
}
