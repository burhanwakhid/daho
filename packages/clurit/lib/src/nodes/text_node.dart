import 'node.dart';

/// A node that outputs literal text.
class TextNode extends Node {
  final String content;

  TextNode(this.content);

  @override
  String compile(Map<String, dynamic> context) => content;
}
