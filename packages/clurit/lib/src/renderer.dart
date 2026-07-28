import 'nodes/node.dart';

/// Renderer that compiles AST nodes with a context to produce HTML.
class Renderer {
  /// Renders a list of [nodes] with the given [context].
  static String render(List<Node> nodes, Map<String, dynamic> context) {
    final buf = StringBuffer();
    for (final node in nodes) {
      buf.write(node.compile(context));
    }
    return buf.toString();
  }
}
