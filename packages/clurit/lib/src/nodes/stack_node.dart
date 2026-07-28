import 'node.dart';

/// A `@stack('name')` placeholder in a layout template.
///
/// Resolved lazily at render time by concatenating every `@push('name')`
/// body registered under [name] (see `CluritEngine._renderTemplate`) — a
/// child template (or any of its includes) may push to the same stack more
/// than once; each push renders in registration order.
class StackNode extends Node {
  final String name;
  StackNode(this.name);

  /// Context key under which the child template's `@push` bodies are
  /// stashed (a `Map<String, List<Node>>`) when rendering a layout it
  /// extends.
  static const stacksContextKey = '__clurit_stacks__';

  @override
  String compile(Map<String, dynamic> context) {
    final stacks = context[stacksContextKey] as Map<String, List<Node>>?;
    final pushed = stacks?[name];
    if (pushed == null) return '';
    final buf = StringBuffer();
    for (final node in pushed) {
      buf.write(node.compile(context));
    }
    return buf.toString();
  }
}
