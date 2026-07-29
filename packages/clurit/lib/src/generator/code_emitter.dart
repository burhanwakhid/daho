import '../nodes/echo_node.dart';
import '../nodes/foreach_node.dart';
import '../nodes/if_node.dart';
import '../nodes/node.dart';
import '../nodes/text_node.dart';
import 'binding_resolver.dart';
import 'code_analyzer.dart';

/// Generates a template's compiled component from its AST plus its
/// `@code` block's [ComponentModel], sharing one binding-id assignment
/// ([BindingModel]) between the server ([emitServer]) and client
/// ([emitClient]) outputs so they can never drift apart.
///
/// Two files are produced:
/// - `<name>.clurit.dart` (from [emitServer]): the reactive fields,
///   computed getters, event handler methods, `renderInitial()` and
///   `initialStateJson()`. No `package:web` import — safe for a server
///   process to depend on.
/// - `<name>.clurit.client.dart` (from [emitClient]): a subclass adding
///   `hydrate()` and the per-binding DOM update closures. Only ever
///   imported by a client (web) entrypoint.
class CodeEmitter {
  final String className;
  final List<Node> templateNodes;
  final ComponentModel component;
  final BindingModel bindings;

  CodeEmitter({
    required this.className,
    required this.templateNodes,
    required this.component,
    required this.bindings,
  });

  // ===========================================================================
  // Server
  // ===========================================================================

  String emitServer() {
    final buf = StringBuffer();
    _writeHeader(buf);
    buf.writeln("import 'package:clurit/clurit.dart';");
    buf.writeln();
    buf.writeln('class $className extends CluritComponent {');
    _emitStateFields(buf);
    _emitDerivedFields(buf);
    _emitPropFields(buf);
    _emitConstructor(buf);
    for (final src in component.plainMemberSources) {
      buf.writeln(src);
      buf.writeln();
    }
    _emitRenderInitial(buf);
    _emitInitialStateJson(buf);
    buf.writeln('}');
    return buf.toString();
  }

  void _emitStateFields(StringBuffer buf) {
    for (final f in component.stateFields) {
      final type = f.type ?? 'dynamic';
      buf.writeln('  $type _${f.name};');
      buf.writeln('  $type get ${f.name} => _${f.name};');
      buf.writeln('  set ${f.name}($type value) {');
      buf.writeln('    if (_${f.name} == value) return;');
      buf.writeln('    _${f.name} = value;');
      buf.writeln("    markDirty('${f.name}');");
      buf.writeln('  }');
      buf.writeln();
    }
  }

  void _emitDerivedFields(StringBuffer buf) {
    for (final f in component.derivedFields) {
      final type = f.type ?? 'dynamic';
      if (f.exprSource != null) {
        buf.writeln('  $type get ${f.name} => ${f.exprSource};');
      } else {
        buf.writeln('  $type get ${f.name} ${f.blockBodySource}');
      }
      buf.writeln();
    }
  }

  void _emitPropFields(StringBuffer buf) {
    for (final f in component.propFields) {
      buf.writeln('  final ${f.type} ${f.name};');
    }
    if (component.propFields.isNotEmpty) buf.writeln();
  }

  void _emitConstructor(StringBuffer buf) {
    final params = <String>[];
    final inits = <String>[];
    for (final f in component.stateFields) {
      final type = f.type ?? 'dynamic';
      // Nullable-optional-with-fallback, rather than `Type name = <initializer>`,
      // since the initializer may be a non-const literal (e.g. `[]`), which
      // Dart's parameter-default-value position requires to be constant.
      final paramType =
          (type == 'dynamic' || type.endsWith('?')) ? type : '$type?';
      params.add('$paramType ${f.name}');
      inits.add('_${f.name} = ${f.name} ?? ${f.initializerSource}');
    }
    for (final f in component.propFields) {
      params.add('required this.${f.name}');
    }
    final paramsSrc = params.isEmpty ? '' : '{${params.join(', ')}}';
    final initSrc = inits.isEmpty ? '' : ' : ${inits.join(', ')}';
    buf.writeln('  $className($paramsSrc)$initSrc;');
    buf.writeln();
  }

  void _emitRenderInitial(StringBuffer buf) {
    buf.writeln('  @override');
    buf.writeln('  String renderInitial() {');
    buf.writeln('    final buf = StringBuffer();');
    _emitNodes(buf, templateNodes, '    ');
    buf.writeln('    return buf.toString();');
    buf.writeln('  }');
    buf.writeln();
  }

  void _emitInitialStateJson(StringBuffer buf) {
    buf.writeln('  @override');
    buf.writeln('  Map<String, dynamic> initialStateJson() => {');
    // Both $state and $props values are included — everything the client
    // needs to reconstruct this exact component at hydrate() time.
    for (final f in component.stateFields) {
      buf.writeln("    '${f.name}': ${f.name},");
    }
    for (final f in component.propFields) {
      buf.writeln("    '${f.name}': ${f.name},");
    }
    buf.writeln('  };');
  }

  /// Emits `buf.write(...)` statements rendering [nodes] — used both for
  /// the server's `renderInitial()` and, identically, for the client's
  /// per-binding fragment-rebuild methods, so a shown/hidden `@if` branch
  /// or a `@foreach` item is rendered by the exact same code path as SSR.
  void _emitNodes(StringBuffer buf, List<Node> nodes, String indent) {
    for (final node in nodes) {
      if (node is TextNode) {
        if (node.content.isEmpty) continue;
        buf.writeln('$indent buf.write(${_dartStringLiteral(node.content)});');
      } else if (node is EchoNode) {
        final expr = toDartExpr(node.expression);
        final valueExpr =
            node.escaped ? 'escapeHtml(stringify($expr))' : 'stringify($expr)';
        if (bindings.has(node)) {
          final id = bindings.idFor(node);
          buf.writeln("$indent buf.write('<!--cl:$id-->');");
          buf.writeln('$indent buf.write($valueExpr);');
          buf.writeln("$indent buf.write('<!--/cl:$id-->');");
        } else {
          // Inside an open HTML attribute value — an anchor comment here
          // would just be broken literal text, not a real DOM comment, so
          // no anchor wrapping. Bind the attribute live via `cl-model` if
          // it needs to stay reactive after hydration.
          buf.writeln('$indent buf.write($valueExpr);');
        }
      } else if (node is IfNode) {
        final id = bindings.idFor(node);
        final cond = toDartExpr(node.condition);
        buf.writeln("$indent buf.write('<!--cl-if:$id-->');");
        buf.writeln('$indent if (ExpressionEvaluator.isTruthy($cond)) {');
        _emitNodes(buf, node.thenBody, '$indent  ');
        if (node.elseBody != null) {
          buf.writeln('$indent } else {');
          _emitNodes(buf, node.elseBody!, '$indent  ');
        }
        buf.writeln('$indent }');
        buf.writeln("$indent buf.write('<!--/cl-if:$id-->');");
      } else if (node is ForeachNode) {
        final id = bindings.idFor(node);
        final iterable = toDartExpr(node.iterableExpr);
        buf.writeln("$indent buf.write('<!--cl-for:$id-->');");
        if (node.key != null) buf.writeln('$indent var _i$id = 0;');
        buf.writeln('$indent for (final ${node.variable} in ($iterable)) {');
        if (node.key != null) {
          buf.writeln('$indent  final ${node.key} = _i$id;');
        }
        _emitNodes(buf, node.body, '$indent  ');
        if (node.key != null) buf.writeln('$indent  _i$id++;');
        buf.writeln('$indent }');
        buf.writeln("$indent buf.write('<!--/cl-for:$id-->');");
      }
    }
  }

  // ===========================================================================
  // Client
  // ===========================================================================

  String emitClient(String serverFileBasename) {
    final clientClassName = '${className}Client';
    final buf = StringBuffer();
    _writeHeader(buf);
    final clientOnlySource = [
      if (component.onInitSource != null) component.onInitSource!,
      if (component.onDestroySource != null) component.onDestroySource!,
      ...component.clientOnlyMemberSources,
    ].join('\n');
    if (clientOnlySource.contains('jsonDecode') ||
        clientOnlySource.contains('jsonEncode')) {
      buf.writeln("import 'dart:convert';");
    }
    if (clientOnlySource.contains('.toJS') ||
        clientOnlySource.contains('.toDart')) {
      buf.writeln("import 'dart:js_interop';");
    }
    buf.writeln("import 'package:clurit/clurit.dart';");
    buf.writeln("import 'package:clurit/clurit_client.dart';");
    buf.writeln("import 'package:web/web.dart' as web;");
    buf.writeln("import '$serverFileBasename';");
    buf.writeln();
    buf.writeln('class $clientClassName extends $className {');
    _emitClientConstructor(buf, clientClassName);
    buf.writeln('  late final CapturedNodes _nodes;');
    buf.writeln();
    _emitHydrate(buf);
    _emitBindingAppliers(buf);
    _emitEffectMethods(buf);
    // Event handler methods that reference package:web (e.g. a "retry"
    // button doing its own fetch) are client-only for the same reason
    // onInit/onDestroy are — see ComponentModel.clientOnlyMemberSources.
    for (final src in component.clientOnlyMemberSources) {
      buf.writeln(src);
      buf.writeln();
    }
    // onInit/onDestroy are client-only: their bodies commonly do browser
    // work (e.g. an initial fetch) that wouldn't compile in the server
    // file, which can't import package:web at all.
    if (component.onInitSource != null) {
      buf.writeln(component.onInitSource);
      buf.writeln();
    }
    if (component.onDestroySource != null) {
      buf.writeln(component.onDestroySource);
      buf.writeln();
    }
    buf.writeln('}');
    return buf.toString();
  }

  void _emitClientConstructor(StringBuffer buf, String clientClassName) {
    final params = <String>[
      for (final f in component.stateFields) 'super.${f.name}',
      for (final f in component.propFields) 'required super.${f.name}',
    ];
    final paramsSrc = params.isEmpty ? '' : '{${params.join(', ')}}';
    buf.writeln('  $clientClassName($paramsSrc);');
    buf.writeln();
  }

  void _emitHydrate(StringBuffer buf) {
    buf.writeln('  Future<void> hydrate(web.Element root) async {');
    buf.writeln('    _nodes = captureClNodes(root);');

    final actionEntries =
        component.eventHandlerNames.map((name) => "'$name': $name").join(', ');
    buf.writeln('    bindActions(_nodes, {$actionEntries});');
    buf.writeln();

    for (final node in templateNodes) {
      final id = _topLevelId(node);
      if (id == null) continue;
      for (final dep in _topLevelDeps(node)) {
        buf.writeln("    registerUpdater('$dep', _applyBinding$id);");
      }
    }

    final modelFields = _modelBoundFields();
    if (modelFields.isNotEmpty) {
      final setters = modelFields
          .map((f) => "'${f.name}': ${_modelSetterExpr(f)}")
          .join(', ');
      buf.writeln('    bindModels(_nodes, {$setters});');
      for (final f in modelFields) {
        buf.writeln(
          "    registerUpdater('${f.name}', () => setModelValue(_nodes, '${f.name}', ${f.name}.toString()));",
        );
      }
      buf.writeln();
    }

    for (var i = 0; i < component.effects.length; i++) {
      for (final dep
          in _fieldsReferencedInDartSource(component.effects[i].bodySource)) {
        buf.writeln("    registerUpdater('$dep', _effect$i);");
      }
    }
    if (component.effects.isNotEmpty) buf.writeln();

    for (var i = 0; i < component.effects.length; i++) {
      buf.writeln('    _effect$i();');
    }

    if (component.hasOnInit) {
      // `await` only compiles against a Future-returning (async) onInit —
      // a synchronous `void onInit() { ... }` can't be awaited at all
      // (`void` isn't a value `await` can operate on).
      final isAsync = RegExp(r'\)\s*async\b').hasMatch(component.onInitSource!);
      buf.writeln(isAsync ? '    await onInit();' : '    onInit();');
    }

    buf.writeln('  }');
    buf.writeln();
  }

  int? _topLevelId(Node node) {
    if ((node is EchoNode || node is IfNode || node is ForeachNode) &&
        bindings.has(node)) {
      return bindings.idFor(node);
    }
    return null;
  }

  Set<String> _topLevelDeps(Node node) {
    if (node is EchoNode) return _fieldsReferencedByBladeExpr(node.expression);
    if (node is IfNode) {
      return {
        ..._fieldsReferencedByBladeExpr(node.condition),
        ..._nestedDeps(node.thenBody),
        if (node.elseBody != null) ..._nestedDeps(node.elseBody!),
      };
    }
    if (node is ForeachNode) {
      return {
        ..._fieldsReferencedByBladeExpr(node.iterableExpr),
        ..._nestedDeps(node.body),
      };
    }
    return const {};
  }

  Set<String> _nestedDeps(List<Node> nodes) {
    final result = <String>{};
    for (final node in nodes) {
      result.addAll(_topLevelDeps(node));
    }
    return result;
  }

  void _emitBindingAppliers(StringBuffer buf) {
    for (final node in templateNodes) {
      if (node is EchoNode) {
        if (!bindings.has(node)) continue; // attribute-context echo, no anchor
        // A binding with no reactive dependency at all (e.g. echoing only
        // a $props value, or a static field) never changes after the
        // initial render — an update closure for it would be dead code,
        // never registered against any field, so skip generating one.
        if (_topLevelDeps(node).isEmpty) continue;
        final id = bindings.idFor(node);
        final expr = toDartExpr(node.expression);
        final valueExpr =
            node.escaped ? 'escapeHtml(stringify($expr))' : 'stringify($expr)';
        buf.writeln('  void _applyBinding$id() {');
        buf.writeln("    _nodes.anchors[$id]!.setText($valueExpr);");
        buf.writeln('  }');
        buf.writeln();
      } else if (node is IfNode) {
        if (_topLevelDeps(node).isEmpty) continue;
        final id = bindings.idFor(node);
        final cond = toDartExpr(node.condition);
        buf.writeln('  void _applyBinding$id() {');
        buf.writeln(
          '    _nodes.anchors[$id]!.setNodes(ExpressionEvaluator.isTruthy($cond) '
          '? _fragment${id}Then() : _fragment${id}Else());',
        );
        buf.writeln('  }');
        buf.writeln();
        _emitFragmentMethod(buf, '_fragment${id}Then', node.thenBody, []);
        _emitFragmentMethod(
            buf, '_fragment${id}Else', node.elseBody ?? const [], []);
      } else if (node is ForeachNode) {
        if (_topLevelDeps(node).isEmpty) continue;
        final id = bindings.idFor(node);
        final iterable = toDartExpr(node.iterableExpr);
        final itemArgs =
            node.key != null ? '${node.variable}, ${node.key}' : node.variable;
        buf.writeln('  void _applyBinding$id() {');
        buf.writeln('    final _items$id = ($iterable);');
        buf.writeln('    final _built$id = <web.Node>[];');
        if (node.key != null) buf.writeln('    var _i$id = 0;');
        buf.writeln('    for (final ${node.variable} in _items$id) {');
        if (node.key != null) {
          buf.writeln('      final ${node.key} = _i$id;');
        }
        buf.writeln('      _built$id.addAll(_fragmentItem$id($itemArgs));');
        if (node.key != null) buf.writeln('      _i$id++;');
        buf.writeln('    }');
        buf.writeln('    _nodes.anchors[$id]!.setNodes(_built$id);');
        buf.writeln('  }');
        buf.writeln();
        final params = node.key != null
            ? 'dynamic ${node.variable}, dynamic ${node.key}'
            : 'dynamic ${node.variable}';
        _emitFragmentMethod(buf, '_fragmentItem$id', node.body, [],
            params: params);
      }
    }
  }

  void _emitFragmentMethod(
    StringBuffer buf,
    String name,
    List<Node> nodes,
    List<String> unusedParams, {
    String params = '',
  }) {
    buf.writeln('  List<web.Node> $name($params) {');
    buf.writeln('    final buf = StringBuffer();');
    _emitNodes(buf, nodes, '    ');
    buf.writeln('    return parseFragment(buf.toString());');
    buf.writeln('  }');
    buf.writeln();
  }

  void _emitEffectMethods(StringBuffer buf) {
    for (var i = 0; i < component.effects.length; i++) {
      buf.writeln('  void _effect$i() ${component.effects[i].bodySource}');
      buf.writeln();
    }
  }

  /// State fields referenced by a `cl-model="fieldName"` attribute
  /// anywhere in the template (a plain text scan — `cl-model` isn't part
  /// of the template AST, it's just characters inside a [TextNode], the
  /// same way `cl-click` is).
  List<StateField> _modelBoundFields() {
    final names = <String>{};
    final pattern = RegExp('''cl-model=["']([a-zA-Z_][a-zA-Z0-9_]*)["']''');

    void visit(List<Node> nodes) {
      for (final node in nodes) {
        if (node is TextNode) {
          names
              .addAll(pattern.allMatches(node.content).map((m) => m.group(1)!));
        } else if (node is IfNode) {
          visit(node.thenBody);
          if (node.elseBody != null) visit(node.elseBody!);
        } else if (node is ForeachNode) {
          visit(node.body);
        }
      }
    }

    visit(templateNodes);
    return component.stateFields.where((f) => names.contains(f.name)).toList();
  }

  /// A type-aware setter closure for a `cl-model`-bound field: the raw
  /// string from the input element is parsed for `int`/`double` fields,
  /// used as-is for `String` (or untyped/`dynamic`) fields.
  String _modelSetterExpr(StateField field) {
    switch (field.type) {
      case 'int':
        return '(v) => ${field.name} = int.tryParse(v) ?? ${field.name}';
      case 'double':
        return '(v) => ${field.name} = double.tryParse(v) ?? ${field.name}';
      default:
        return '(v) => ${field.name} = v';
    }
  }

  Set<String> _fieldsReferencedByBladeExpr(String expr) {
    final refs = RegExp(
      r'\$([a-zA-Z_][a-zA-Z0-9_]*)',
    ).allMatches(expr).map((m) => m.group(1)!);
    return _classifyFieldRefs(refs);
  }

  Set<String> _fieldsReferencedInDartSource(String dartSource) {
    final allNames = [
      ...component.stateFields.map((f) => f.name),
      ...component.derivedFields.map((f) => f.name),
    ];
    final refs = allNames.where(
      (name) =>
          RegExp(r'\b' + RegExp.escape(name) + r'\b').hasMatch(dartSource),
    );
    return _classifyFieldRefs(refs);
  }

  Set<String> _classifyFieldRefs(Iterable<String> refs) {
    final stateNames = component.stateFields.map((f) => f.name).toSet();
    final derivedNames = component.derivedFields.map((f) => f.name).toSet();
    final result = <String>{};
    for (final r in refs) {
      if (stateNames.contains(r)) result.add(r);
      if (derivedNames.contains(r)) result.addAll(stateNames);
    }
    return result;
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln('// Regenerate with: dart run build_runner build');
    buf.writeln('// ignore_for_file: type=lint');
    buf.writeln();
  }
}

/// Translates a Clurit/Blade-style expression (`$count > 10`, `$user->name`)
/// into a plain Dart expression referencing the generated component's own
/// fields/getters (`count > 10`, `user.name`).
///
/// This is a textual, not semantic, translation — it is not aware of string
/// literals inside the expression, so a literal containing `$name` or `->`
/// would be (incorrectly) rewritten too. Acceptable for now: template
/// conditions/echoes are overwhelmingly bare variable/property expressions.
String toDartExpr(String expr) {
  var out = expr.replaceAll('->', '.');
  out = out.replaceAllMapped(
    RegExp(r'\$([a-zA-Z_][a-zA-Z0-9_]*)'),
    (m) => m.group(1)!,
  );
  return out;
}

String _dartStringLiteral(String s) {
  final buf = StringBuffer("'");
  for (final rune in s.runes) {
    final c = String.fromCharCode(rune);
    switch (c) {
      case '\\':
        buf.write(r'\\');
        break;
      case "'":
        buf.write(r"\'");
        break;
      case r'$':
        buf.write(r'\$');
        break;
      case '\n':
        buf.write(r'\n');
        break;
      case '\r':
        buf.write(r'\r');
        break;
      default:
        buf.write(c);
    }
  }
  buf.write("'");
  return buf.toString();
}
