import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// A reactive `$state(initial)` field found in an `@code` block.
class StateField {
  final String name;
  final String? type;
  final String initializerSource;

  StateField({required this.name, this.type, required this.initializerSource});
}

/// A computed `$derived(expr)` / `$derived.by(() { ... })` field.
class DerivedField {
  final String name;
  final String? type;

  /// Set when authored as `$derived(expr)` — a single expression.
  final String? exprSource;

  /// Set when authored as `$derived.by(() { ... })` — a full function body
  /// (`{ ...; return x; }` or `=> x;`), pasted directly after `get name`.
  final String? blockBodySource;

  DerivedField({
    required this.name,
    this.type,
    this.exprSource,
    this.blockBodySource,
  }) : assert(
          (exprSource == null) != (blockBodySource == null),
          'exactly one of exprSource/blockBodySource must be set',
        );
}

/// A `$props()` field — a value sourced from the component's initial render
/// data, exposed as a constructor parameter with no generated setter.
class PropField {
  final String name;
  final String type;
  final String? overrideName;

  PropField({required this.name, required this.type, this.overrideName});
}

/// A `$effect(() { ... })` side effect found inside `onInit()`.
class EffectModel {
  final String bodySource;

  EffectModel({required this.bodySource});
}

/// The classified contents of an `@code { }` block, ready for code
/// generation.
class ComponentModel {
  final List<StateField> stateFields;
  final List<DerivedField> derivedFields;
  final List<PropField> propFields;
  final List<EffectModel> effects;

  /// Verbatim source of every member that isn't a rune declaration and
  /// isn't `onInit`/`onDestroy` (see [onInitSource]/[onDestroySource]):
  /// event handler methods, plain non-reactive fields, etc. Pasted as-is
  /// into the generated class body — on **both** the server and client
  /// outputs.
  final List<String> plainMemberSources;

  /// Names of event handler methods (non-getter/setter methods other than
  /// `onInit`/`onDestroy`), used by the client emitter to wire `cl-click`
  /// bindings without needing to re-parse [plainMemberSources] or
  /// [clientOnlyMemberSources].
  final List<String> eventHandlerNames;

  /// Verbatim source of event handler methods that reference `web.`
  /// (`package:web`'s browser APIs) anywhere in their body — e.g. a
  /// "retry" button's handler doing its own `web.window.fetch(...)`.
  /// Emitted **only** client-side, same reasoning as [onInitSource]: the
  /// server file can't import `package:web` at all. This is a textual,
  /// not semantic, detection (a method merely containing the substring
  /// `web.` some other way would also be routed here) — a reasonable
  /// trade-off given `web` is reserved for this import in every generated
  /// file, so a false positive would need a local identifier deliberately
  /// named `web.something`, which is not a name anyone would pick.
  final List<String> clientOnlyMemberSources;

  /// The declared `onInit()`'s source (with any `$effect(...)` statements
  /// stripped out — those are registered separately), if any. Emitted
  /// **only** in the client output, never the server one: `onInit` is only
  /// ever called from `hydrate()`, and unlike other plain members, its body
  /// commonly does browser-only work (e.g. `web.window.fetch(...)` to load
  /// data once mounted) that wouldn't compile in the server file, which
  /// can't import `package:web` at all (it must stay usable on a native
  /// server runtime).
  final String? onInitSource;

  /// Same treatment as [onInitSource], for `onDestroy()`.
  final String? onDestroySource;

  /// Whether an `onInit()` lifecycle hook was declared — if so, the client
  /// emitter calls it once from `hydrate()` (awaited, so an `async onInit`
  /// doing e.g. an initial data fetch works correctly). A hook containing
  /// only `$effect(...)` statements still counts: its (now-empty) shell is
  /// harmless to call, and the extracted effects still need to run once at
  /// mount regardless.
  bool get hasOnInit => onInitSource != null;

  ComponentModel({
    required this.stateFields,
    required this.derivedFields,
    required this.propFields,
    required this.effects,
    required this.plainMemberSources,
    required this.eventHandlerNames,
    this.clientOnlyMemberSources = const [],
    this.onInitSource,
    this.onDestroySource,
  });
}

/// Parses the Dart-like source inside an `@code { }` block with
/// `package:analyzer` (real Dart parsing, not regex) and classifies its
/// members by rune call shape.
class CodeAnalyzer {
  static ComponentModel analyze(String codeBlockSource) {
    final wrapped = 'class _CluritComponent {\n$codeBlockSource\n}';
    final parseResult =
        parseString(content: wrapped, throwIfDiagnostics: false);
    final classDecl =
        parseResult.unit.declarations.whereType<ClassDeclaration>().first;

    final stateFields = <StateField>[];
    final derivedFields = <DerivedField>[];
    final propFields = <PropField>[];
    final effects = <EffectModel>[];
    final plainMembers = <String>[];
    final clientOnlyMembers = <String>[];
    final eventHandlerNames = <String>[];
    final lifecycleSources = <String, String>{};

    for (final member in classDecl.members) {
      if (member is FieldDeclaration) {
        _classifyField(
          member,
          stateFields: stateFields,
          derivedFields: derivedFields,
          propFields: propFields,
          plainMembers: plainMembers,
        );
      } else if (member is MethodDeclaration) {
        _classifyMethod(
          member,
          effects: effects,
          plainMembers: plainMembers,
          clientOnlyMembers: clientOnlyMembers,
          eventHandlerNames: eventHandlerNames,
          lifecycleSources: lifecycleSources,
        );
      } else {
        plainMembers.add(member.toSource());
      }
    }

    return ComponentModel(
      stateFields: stateFields,
      derivedFields: derivedFields,
      propFields: propFields,
      effects: effects,
      plainMemberSources: plainMembers,
      clientOnlyMemberSources: clientOnlyMembers,
      eventHandlerNames: eventHandlerNames,
      onInitSource: lifecycleSources['onInit'],
      onDestroySource: lifecycleSources['onDestroy'],
    );
  }

  static void _classifyField(
    FieldDeclaration member, {
    required List<StateField> stateFields,
    required List<DerivedField> derivedFields,
    required List<PropField> propFields,
    required List<String> plainMembers,
  }) {
    final declaredType = member.fields.type?.toSource();
    var anyRune = false;

    for (final variable in member.fields.variables) {
      final init = variable.initializer;
      if (init is! MethodInvocation) continue;

      final name = variable.name.lexeme;
      final args = init.argumentList.arguments;

      if (init.target == null &&
          init.methodName.name == r'$state' &&
          args.length == 1) {
        final typeArg = init.typeArguments?.arguments;
        final type = declaredType ??
            (typeArg != null && typeArg.isNotEmpty
                ? typeArg.first.toSource()
                : _inferLiteralType(args.first));
        stateFields.add(
          StateField(
            name: name,
            type: type,
            initializerSource: args.first.toSource(),
          ),
        );
        anyRune = true;
        continue;
      }

      if (init.target == null &&
          init.methodName.name == r'$derived' &&
          args.length == 1) {
        derivedFields.add(
          DerivedField(
              name: name,
              type: declaredType,
              exprSource: args.first.toSource()),
        );
        anyRune = true;
        continue;
      }

      final target = init.target;
      if (target is SimpleIdentifier &&
          target.name == r'$derived' &&
          init.methodName.name == 'by' &&
          args.length == 1 &&
          args.first is FunctionExpression) {
        derivedFields.add(
          DerivedField(
            name: name,
            type: declaredType,
            blockBodySource:
                _functionBodySource(args.first as FunctionExpression),
          ),
        );
        anyRune = true;
        continue;
      }

      if (init.target == null && init.methodName.name == r'$props') {
        String? overrideName;
        if (args.isNotEmpty && args.first is StringLiteral) {
          overrideName = (args.first as StringLiteral).stringValue;
        }
        final typeArg = init.typeArguments?.arguments;
        final type = declaredType ??
            (typeArg != null && typeArg.isNotEmpty
                ? typeArg.first.toSource()
                : 'dynamic');
        propFields
            .add(PropField(name: name, type: type, overrideName: overrideName));
        anyRune = true;
        continue;
      }
    }

    if (!anyRune) {
      plainMembers.add(member.toSource());
    }
  }

  static void _classifyMethod(
    MethodDeclaration member, {
    required List<EffectModel> effects,
    required List<String> plainMembers,
    required List<String> clientOnlyMembers,
    required List<String> eventHandlerNames,
    required Map<String, String> lifecycleSources,
  }) {
    final isLifecycleHook =
        (member.name.lexeme == 'onInit' || member.name.lexeme == 'onDestroy') &&
            !member.isGetter &&
            !member.isSetter;

    if (!isLifecycleHook || member.body is! BlockFunctionBody) {
      if (isLifecycleHook) {
        lifecycleSources[member.name.lexeme] = member.toSource();
      } else {
        final source = member.toSource();
        if (_usesClientOnlyApi(source)) {
          clientOnlyMembers.add(source);
        } else {
          plainMembers.add(source);
        }
        if (!member.isGetter && !member.isSetter) {
          eventHandlerNames.add(member.name.lexeme);
        }
      }
      return;
    }

    final block = (member.body as BlockFunctionBody).block;
    final remainingStatements = <String>[];
    var foundEffect = false;

    for (final statement in block.statements) {
      final effectFn = _matchEffectCall(statement);
      if (effectFn != null) {
        effects.add(EffectModel(bodySource: _functionBodySource(effectFn)));
        foundEffect = true;
      } else {
        remainingStatements.add(statement.toSource());
      }
    }

    if (!foundEffect) {
      lifecycleSources[member.name.lexeme] = member.toSource();
      return;
    }

    if (remainingStatements.isNotEmpty) {
      final returnType = member.returnType?.toSource() ?? 'void';
      lifecycleSources[member.name.lexeme] =
          '$returnType ${member.name.lexeme}() {\n${remainingStatements.join('\n')}\n}';
    } else {
      // Every statement was an $effect(...) call — the method body is now
      // empty, but the client emitter (CodeEmitter._emitHydrate) always
      // calls a declared onInit()/onDestroy(), so it must still exist.
      lifecycleSources[member.name.lexeme] = 'void ${member.name.lexeme}() {}';
    }
  }

  static final _clientOnlyApiPattern = RegExp(
    r'\bweb\.\w|\bonInit\s*\(|\bonDestroy\s*\(',
  );

  /// Whether [source] references `package:web`'s browser APIs (`web.` —
  /// the import alias every generated file uses) or calls `onInit()`/
  /// `onDestroy()` (client-only themselves, e.g. a "retry" button
  /// re-running `onInit()`'s fetch) — either way, this member must be
  /// emitted client-only too, transitively.
  static bool _usesClientOnlyApi(String source) =>
      _clientOnlyApiPattern.hasMatch(source);

  /// Returns the `$effect(() { ... })`'s closure, if [statement] is exactly
  /// an `$effect(...)` call expression statement.
  static FunctionExpression? _matchEffectCall(Statement statement) {
    if (statement is! ExpressionStatement) return null;
    final expr = statement.expression;
    if (expr is! MethodInvocation) return null;
    if (expr.target != null || expr.methodName.name != r'$effect') return null;
    final args = expr.argumentList.arguments;
    if (args.length != 1 || args.first is! FunctionExpression) return null;
    return args.first as FunctionExpression;
  }

  /// Infers a field's Dart type from a `$state(initial)`/`$props()` literal
  /// initial-value expression when no declared type is present, so
  /// generated fields aren't needlessly typed `dynamic`.
  static String? _inferLiteralType(Expression expr) {
    if (expr is IntegerLiteral) return 'int';
    if (expr is DoubleLiteral) return 'double';
    if (expr is BooleanLiteral) return 'bool';
    if (expr is StringLiteral) return 'String';
    if (expr is ListLiteral) return 'List';
    if (expr is SetOrMapLiteral) return 'Map';
    if (expr is PrefixExpression && expr.operator.lexeme == '-') {
      return _inferLiteralType(expr.operand);
    }
    return null;
  }

  static String _functionBodySource(FunctionExpression fn) {
    final body = fn.body;
    if (body is BlockFunctionBody) return body.block.toSource();
    if (body is ExpressionFunctionBody)
      return '=> ${body.expression.toSource()};';
    return body.toSource();
  }
}
