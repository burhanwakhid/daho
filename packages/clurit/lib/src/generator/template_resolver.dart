import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import '../lexer.dart';
import '../nodes/foreach_node.dart';
import '../nodes/if_node.dart';
import '../nodes/include_node.dart';
import '../nodes/node.dart';
import '../nodes/stack_node.dart';
import '../nodes/text_node.dart';
import '../nodes/yield_node.dart';
import '../parser.dart';

/// Resolves a `.clurit` file's `@extends`/`@section`/`@yield`/`@stack`/
/// `@include` composition into one flat, self-contained node list — the
/// same composition [CluritEngine] does dynamically at render time (see
/// `engine.dart`'s `_renderTemplate`), but done once at build time, since
/// the reactive-component generator (`CodeEmitter`) walks a single
/// template's AST directly and has no notion of layouts/sections/includes
/// on its own.
///
/// Without this, `@code` inside a `@section` (or content behind an
/// `@include`) is silently dropped — `findCodeNodes`/`BindingResolver`/
/// `CodeEmitter` only ever see `TextNode`/`EchoNode`/`IfNode`/`ForeachNode`;
/// a `DeferredBodyNode` (`@section`/`@push`), `IncludeNode`, `YieldNode`, or
/// `StackNode` reaching them produces no output at all.
///
/// Nested `@extends` (a layout that itself extends another layout) isn't
/// supported, matching `CluritEngine`'s own documented limitation.
Future<List<Node>> resolveTemplateNodes(BuildStep buildStep, AssetId inputId) async {
  final viewsRoot = _viewsRootFor(inputId.path);
  final source = await buildStep.readAsString(inputId);
  final tokens = Lexer.tokenize(source);
  final parser = Parser(tokens, includeResolver: _includeMarkerResolver);
  final nodes = parser.parse();

  if (parser.extendsLayout == null) {
    return _resolveIncludesAndFlatten(buildStep, viewsRoot, nodes);
  }

  final resolvedSections = <String, List<Node>>{};
  for (final entry in parser.sections.entries) {
    resolvedSections[entry.key] = await _resolveIncludesAndFlatten(
      buildStep,
      viewsRoot,
      _bodyOf(entry.value),
    );
  }

  final resolvedPushes = <String, List<Node>>{};
  for (final entry in parser.pushes.entries) {
    final combined = <Node>[];
    for (final pushed in entry.value) {
      combined.addAll(
        await _resolveIncludesAndFlatten(buildStep, viewsRoot, _bodyOf(pushed)),
      );
    }
    resolvedPushes[entry.key] = combined;
  }

  final layoutId = _assetForDottedName(inputId.package, viewsRoot, parser.extendsLayout!);
  final layoutNodes = await _parseFile(buildStep, layoutId);
  final resolvedLayoutNodes = await _resolveIncludesAndFlatten(buildStep, viewsRoot, layoutNodes);
  final splicedLayoutNodes = _spliceYieldsAndStacks(resolvedLayoutNodes, resolvedSections, resolvedPushes);

  // The child template's own top-level content that ISN'T a registered
  // @section/@push body (most commonly, an `@code { }` block declared
  // before `@extends(...)`, as every example in this project does) is
  // otherwise silently dropped — `@section`/`@push` bodies get relocated
  // into the layout via @yield/@stack, but nothing else the child
  // declares at its own top level has anywhere to go unless we keep it.
  // It doesn't render any visible HTML of its own (findCodeNodes just
  // looks for it in the resolved tree), so prepending it is safe.
  final registeredBodies = <Node>{
    ...parser.sections.values,
    for (final pushList in parser.pushes.values) ...pushList,
  };
  final ownTopLevelNodes = nodes.where((n) => !registeredBodies.contains(n)).toList();
  final resolvedOwnNodes = await _resolveIncludesAndFlatten(buildStep, viewsRoot, ownTopLevelNodes);

  return [...resolvedOwnNodes, ...splicedLayoutNodes];
}

List<Node> _bodyOf(Node node) => node is DeferredBodyNode ? node.body : [node];

/// A dotted `@include`/`@extends` name is always resolved relative to the
/// app's `views/` root — not the including file's own directory — matching
/// `CluritEngine`'s convention (`layoutName.replaceAll('.', p.separator)`
/// joined onto `viewsPath`).
String _viewsRootFor(String assetPath) {
  final segments = p.posix.split(assetPath);
  final viewsIndex = segments.lastIndexOf('views');
  if (viewsIndex == -1) return p.posix.dirname(assetPath);
  return p.posix.joinAll(segments.sublist(0, viewsIndex + 1));
}

AssetId _assetForDottedName(String package, String viewsRoot, String dottedName) {
  final relative = dottedName.replaceAll('.', '/');
  return AssetId(package, p.posix.join(viewsRoot, '$relative.clurit'));
}

Future<List<Node>> _parseFile(BuildStep buildStep, AssetId assetId) async {
  final source = await buildStep.readAsString(assetId);
  final tokens = Lexer.tokenize(source);
  return Parser(tokens, includeResolver: _includeMarkerResolver).parse();
}

/// The [Parser]'s `includeResolver` callback is synchronous, but resolving
/// an `@include` here means reading another file (async) — so parsing
/// leaves an [IncludeNode] marker in place (its `template` name is all we
/// need), and [_resolveIncludesAndFlatten] replaces it with the real,
/// recursively-resolved content afterward.
Node _includeMarkerResolver(String template, Map<String, dynamic>? data) {
  return IncludeNode(template: template, data: data, resolver: (_, __) => TextNode(''));
}

/// Recursively replaces every [IncludeNode] marker with its target file's
/// own (recursively resolved) nodes, and inlines every [DeferredBodyNode]
/// (transparent outside of `@section`/`@push`, which are handled by the
/// caller before this ever sees them) — descending into `@if`/`@foreach`
/// bodies so nested includes there are resolved too.
Future<List<Node>> _resolveIncludesAndFlatten(
  BuildStep buildStep,
  String viewsRoot,
  List<Node> nodes,
) async {
  final result = <Node>[];
  for (final node in nodes) {
    if (node is DeferredBodyNode) {
      result.addAll(await _resolveIncludesAndFlatten(buildStep, viewsRoot, node.body));
    } else if (node is IncludeNode) {
      final assetId = _assetForDottedName(buildStep.inputId.package, viewsRoot, node.template);
      final includedNodes = await _parseFile(buildStep, assetId);
      result.addAll(await _resolveIncludesAndFlatten(buildStep, viewsRoot, includedNodes));
    } else if (node is IfNode) {
      result.add(
        IfNode(
          condition: node.condition,
          thenBody: await _resolveIncludesAndFlatten(buildStep, viewsRoot, node.thenBody),
          elseBody: node.elseBody != null
              ? await _resolveIncludesAndFlatten(buildStep, viewsRoot, node.elseBody!)
              : null,
        ),
      );
    } else if (node is ForeachNode) {
      result.add(
        ForeachNode(
          iterableExpr: node.iterableExpr,
          variable: node.variable,
          key: node.key,
          body: await _resolveIncludesAndFlatten(buildStep, viewsRoot, node.body),
        ),
      );
    } else {
      result.add(node);
    }
  }
  return result;
}

/// Walks a (already include-resolved) layout's nodes, replacing every
/// [YieldNode] with the matching resolved `@section` body (nothing, if the
/// child didn't provide that section — matching `YieldNode`'s own runtime
/// default) and every [StackNode] with its concatenated `@push` bodies.
List<Node> _spliceYieldsAndStacks(
  List<Node> nodes,
  Map<String, List<Node>> sections,
  Map<String, List<Node>> pushes,
) {
  final result = <Node>[];
  for (final node in nodes) {
    if (node is YieldNode) {
      result.addAll(sections[node.name] ?? const []);
    } else if (node is StackNode) {
      result.addAll(pushes[node.name] ?? const []);
    } else if (node is IfNode) {
      result.add(
        IfNode(
          condition: node.condition,
          thenBody: _spliceYieldsAndStacks(node.thenBody, sections, pushes),
          elseBody: node.elseBody != null
              ? _spliceYieldsAndStacks(node.elseBody!, sections, pushes)
              : null,
        ),
      );
    } else if (node is ForeachNode) {
      result.add(
        ForeachNode(
          iterableExpr: node.iterableExpr,
          variable: node.variable,
          key: node.key,
          body: _spliceYieldsAndStacks(node.body, sections, pushes),
        ),
      );
    } else {
      result.add(node);
    }
  }
  return result;
}
