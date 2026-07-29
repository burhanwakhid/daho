import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import '../nodes/code_node.dart';
import '../nodes/foreach_node.dart';
import '../nodes/if_node.dart';
import '../nodes/node.dart';
import 'binding_resolver.dart';
import 'code_analyzer.dart';
import 'code_emitter.dart';
import 'template_resolver.dart';

/// Builder factory matching `build.yaml`'s `clurit_action_builder` entry.
Builder cluritActionBuilder(BuilderOptions options) => CluritGenerator();

/// Compiles a `.clurit` template's `@code { }` block into a generated
/// `CluritComponent` subclass — real Dart parsing of `@code` (via
/// `package:analyzer` in [CodeAnalyzer]) plus a single binding-id pass
/// ([BindingResolver]) shared between the SSR render and (in a later
/// phase) client hydration, so the two can never drift out of sync.
///
/// Templates with no `@code` block are left alone — nothing is generated.
class CluritGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        '.clurit': ['.clurit.dart', '.clurit.client.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final nodes = await resolveTemplateNodes(buildStep, buildStep.inputId);

    final codeNodes = findCodeNodes(nodes);
    if (codeNodes.isEmpty) return;

    final component = CodeAnalyzer.analyze(codeNodes.first.code);
    final bindings = BindingResolver.resolve(nodes);
    final className = classNameFor(buildStep.inputId);

    final emitter = CodeEmitter(
      className: className,
      templateNodes: nodes,
      component: component,
      bindings: bindings,
    );

    final serverId = buildStep.inputId.changeExtension('.clurit.dart');
    await buildStep.writeAsString(serverId, emitter.emitServer());
    await buildStep.writeAsString(
      buildStep.inputId.changeExtension('.clurit.client.dart'),
      emitter.emitClient(p.basename(serverId.path)),
    );
  }
}

/// Recursively finds every `@code { }` block in a template's AST.
List<CodeNode> findCodeNodes(List<Node> nodes) {
  final result = <CodeNode>[];

  void visit(List<Node> list) {
    for (final node in list) {
      if (node is CodeNode) {
        result.add(node);
      } else if (node is IfNode) {
        visit(node.thenBody);
        if (node.elseBody != null) visit(node.elseBody!);
      } else if (node is ForeachNode) {
        visit(node.body);
      }
    }
  }

  visit(nodes);
  return result;
}

/// Derives a `PascalCaseComponent` class name from a `.clurit` file's path,
/// e.g. `views/pages/counter.clurit` -> `CounterComponent`.
String classNameFor(AssetId id) {
  final base = p.basenameWithoutExtension(id.path);
  final pascal = base
      .split(RegExp(r'[_\-\.\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
  return '${pascal}Component';
}
