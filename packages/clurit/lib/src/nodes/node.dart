/// Base class for all AST nodes in the Clurit template engine.
abstract class Node {
  /// Compiles this node to an HTML string using the given [context].
  String compile(Map<String, dynamic> context);
}
