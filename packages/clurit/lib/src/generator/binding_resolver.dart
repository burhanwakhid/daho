import '../nodes/echo_node.dart';
import '../nodes/foreach_node.dart';
import '../nodes/if_node.dart';
import '../nodes/node.dart';
import '../nodes/text_node.dart';

/// Assigns stable, sequential binding ids to every reactive binding site
/// (`{{ }}` echoes, `@if`, `@foreach`) in a template's AST, in document
/// order. The same ids are baked into the generated `renderInitial()`
/// output as anchor-comment markers, so a later hydration pass can locate
/// each binding's DOM range without any runtime scanning.
///
/// Echoes inside an open HTML attribute value (e.g. `value="{{ $x }}"`)
/// are deliberately left without an id — an anchor comment inside an
/// attribute value string isn't a real DOM comment, it's just broken
/// literal text, so there is no anchor to wrap them with. Such echoes
/// still render their value (see `CodeEmitter._emitNodes`); if the
/// attribute itself needs to stay live after hydration, bind it
/// explicitly via `cl-model`.
class BindingModel {
  final Map<Node, int> ids;

  BindingModel(this.ids);

  bool has(Node node) => ids.containsKey(node);

  int idFor(Node node) => ids[node]!;
}

class BindingResolver {
  static BindingModel resolve(List<Node> nodes) {
    final ids = <Node, int>{};
    var next = 0;

    // A minimal streaming scan of literal HTML text — not a real parser —
    // just enough to know whether we're currently inside an open,
    // quoted attribute value when an echo is encountered.
    var insideTag = false;
    var insideAttr = false;
    var quoteChar = '"';

    void scanText(String text) {
      for (final rune in text.runes) {
        final c = String.fromCharCode(rune);
        if (insideAttr) {
          if (c == quoteChar) insideAttr = false;
        } else if (insideTag) {
          if (c == '"' || c == "'") {
            insideAttr = true;
            quoteChar = c;
          } else if (c == '>') {
            insideTag = false;
          }
        } else if (c == '<') {
          insideTag = true;
        }
      }
    }

    void visit(List<Node> list) {
      for (final node in list) {
        if (node is TextNode) {
          scanText(node.content);
        } else if (node is EchoNode) {
          if (!insideAttr) ids[node] = next++;
        } else if (node is IfNode) {
          ids[node] = next++;
          visit(node.thenBody);
          if (node.elseBody != null) visit(node.elseBody!);
        } else if (node is ForeachNode) {
          ids[node] = next++;
          visit(node.body);
        }
      }
    }

    visit(nodes);
    return BindingModel(ids);
  }
}
