import 'node.dart';

/// A node for @component/@slot/@endcomponent.
class ComponentNode extends Node {
  final String template;
  final Map<String, dynamic> data;
  final Map<String, List<Node>> slots;
  final Node Function(String template, Map<String, dynamic> data) resolver;

  ComponentNode({
    required this.template,
    required this.data,
    required this.slots,
    required this.resolver,
  });

  @override
  String compile(Map<String, dynamic> context) {
    final componentContext = Map<String, dynamic>.from(context);
    componentContext.addAll(data);

    // Compile slots
    for (final entry in slots.entries) {
      final slotBuf = StringBuffer();
      for (final node in entry.value) {
        slotBuf.write(node.compile(context));
      }
      componentContext[entry.key] = slotBuf.toString();
    }

    // Default slot (body content)
    if (slots.containsKey('default')) {
      componentContext['slot'] = componentContext['default'];
    }

    final resolved = resolver(template, componentContext);
    return resolved.compile(componentContext);
  }
}
