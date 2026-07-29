import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'clurit_generator.dart';
import 'code_analyzer.dart';
import 'template_resolver.dart';

/// Builder factory matching `build.yaml`'s `clurit_routes_builder` entry.
Builder cluritRoutesBuilder(BuilderOptions options) => CluritRoutesBuilder();

/// Generates two files from one scan of an app's `views/` directory:
///
/// - `web/main.g.dart` — a client bootstrap that hydrates whichever page's
///   compiled component matches the current URL, wiring [CluritRouter] for
///   SPA navigation between them (deferred imports, a `switch` on
///   `location.pathname`, extracting each field back out of
///   `readInitialState()` with the right cast).
/// - `clurit_components.g.dart` — a server-side `Map<String, ...>` factory
///   registry (the same field extraction, but reading a `data` map instead
///   of `readInitialState()`), for `CluritDahoExtension.configureClurit`'s
///   `components` parameter — no more hand-writing one `registerComponent`
///   call per page.
///
/// Triggered by a marker file, `clurit_routes.yaml`, at the app root next
/// to `main.dart` (content ignored — its only job is giving this
/// aggregating builder a real per-app input, since `build_runner` requires
/// build_extensions' outputs to be statically knowable per input, not
/// invented at runtime). Scans every `.clurit` file with an `@code` block
/// under the sibling `views/` directory and derives each one's route path
/// from its filename: `index` or `home` -> `/`, anything else -> `/<name>`
/// (matching, e.g., Next.js's pages-directory convention).
///
/// Regenerate after adding/removing a page or changing its `$state`/
/// `$props` fields — like every other generated file here, never hand-edit
/// `main.g.dart`/`clurit_components.g.dart` themselves.
class CluritRoutesBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        'clurit_routes.yaml': ['web/main.g.dart', 'clurit_components.g.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final triggerId = buildStep.inputId;
    final appRoot = p.dirname(triggerId.path);
    final webDir = p.posix.join(appRoot, 'web');
    final viewsGlob = Glob('$appRoot/views/{**/,}*.clurit');

    final pages = <PageRoute>[];
    await for (final asset in buildStep.findAssets(viewsGlob)) {
      final nodes = await resolveTemplateNodes(buildStep, asset);
      final codeNodes = findCodeNodes(nodes);
      if (codeNodes.isEmpty) continue; // plain template, nothing to hydrate

      final component = ComponentAnalyzerResult(
        model: CodeAnalyzer.analyze(codeNodes.first.code),
        className: classNameFor(asset),
        clientImportPath: p.posix.relative(
          '${p.withoutExtension(asset.path)}.clurit.client.dart',
          from: webDir,
        ),
        serverImportPath: p.posix.relative(
          '${p.withoutExtension(asset.path)}.clurit.dart',
          from: appRoot,
        ),
      );
      pages.add(PageRoute(routeFor(asset), component));
    }

    // Deterministic output regardless of filesystem iteration order.
    pages.sort((a, b) => a.path.compareTo(b.path));

    await buildStep.writeAsString(
      AssetId(triggerId.package, p.posix.join(webDir, 'main.g.dart')),
      emitClientBootstrap(pages),
    );
    await buildStep.writeAsString(
      AssetId(
          triggerId.package, p.posix.join(appRoot, 'clurit_components.g.dart')),
      emitComponentRegistry(pages),
    );
  }

  // ===========================================================================
  // Client bootstrap (web/main.g.dart)
  // ===========================================================================

  String emitClientBootstrap(List<PageRoute> pages) {
    final buf = StringBuffer();
    _writeHeader(buf);
    buf.writeln("import 'package:clurit/clurit_client.dart';");
    buf.writeln("import 'package:web/web.dart' as web;");
    buf.writeln();
    for (var i = 0; i < pages.length; i++) {
      buf.writeln(
          "import '${pages[i].component.clientImportPath}' deferred as _page$i;");
    }
    buf.writeln();
    buf.writeln('Future<void> hydrateCurrentPage(web.Element root) async {');
    buf.writeln('  final state = readInitialState();');
    buf.writeln('  switch (web.window.location.pathname) {');
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.path == '/') continue; // emitted as `default` below
      buf.writeln("    case '${page.path}':");
      _emitClientCase(buf, i, page.component);
    }
    buf.writeln('    default:');
    final home = pages.indexWhere((r) => r.path == '/');
    if (home != -1) {
      _emitClientCase(buf, home, pages[home].component);
    } else {
      buf.writeln('      break;');
    }
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('void main() {');
    buf.writeln("  final root = web.document.querySelector('#app');");
    buf.writeln('  if (root == null) return;');
    buf.writeln('  hydrateCurrentPage(root);');
    buf.writeln('  CluritRouter(');
    buf.writeln('    onHydrate: hydrateCurrentPage,');
    buf.writeln("    contentSelector: '#app',");
    buf.writeln('  ).init();');
    buf.writeln('}');
    return buf.toString();
  }

  void _emitClientCase(
      StringBuffer buf, int index, ComponentAnalyzerResult component) {
    buf.writeln('      await _page$index.loadLibrary();');
    final args = _fieldArgs(component, source: 'state');
    buf.writeln(
      '      _page$index.${component.className}Client(${args.join(', ')}).hydrate(root);',
    );
    buf.writeln('      break;');
  }

  // ===========================================================================
  // Server component registry (clurit_components.g.dart)
  // ===========================================================================

  String emitComponentRegistry(List<PageRoute> pages) {
    final buf = StringBuffer();
    _writeHeader(buf);
    buf.writeln("import 'package:clurit/clurit.dart';");
    for (final page in pages) {
      buf.writeln("import '${page.component.serverImportPath}';");
    }
    buf.writeln();
    buf.writeln(
        'final Map<String, CluritComponent Function(Map<String, dynamic>)> '
        'cluritComponents = {');
    for (final page in pages) {
      final args = _fieldArgs(page.component, source: 'data');
      buf.writeln(
        "  '${page.registryKey}': (data) => ${page.component.className}(${args.join(', ')}),",
      );
    }
    buf.writeln('};');
    return buf.toString();
  }

  // ===========================================================================
  // Shared field-extraction logic
  // ===========================================================================

  /// Named constructor arguments (`field: <extraction expr>`) for every
  /// `$state`/`$props` field on [component], reading each back out of a
  /// `Map<String, dynamic>` named [source] (`state` on the client,
  /// `data` on the server) — the same shape either side needs to
  /// reconstruct the component from its serialized fields.
  List<String> _fieldArgs(ComponentAnalyzerResult component,
      {required String source}) {
    return [
      // $state fields: the generated component's own constructor param is
      // nullable-optional-with-fallback (`int? count`, defaulted via `??`
      // in its initializer list — see CodeEmitter._emitConstructor), so a
      // nullable extraction here is correct even if the key is missing.
      for (final f in component.model.stateFields)
        '${f.name}: ${_extractExpr(f.type, f.name, source, nullable: true)}',
      // $props fields are required and non-nullable on the generated
      // component (`required this.title;` typed `String`, no fallback) —
      // extraction must match, a non-null cast that throws clearly if the
      // caller forgot to supply it, rather than silently passing null into
      // a non-nullable required parameter.
      for (final f in component.model.propFields)
        '${f.name}: ${_extractExpr(f.type, f.name, source, nullable: false)}',
    ];
  }

  /// Best-effort typed extraction of a field's value out of a decoded JSON
  /// map — mirroring the casts a hand-written bootstrap/registry would use.
  /// `List<T>`/`Map<String, T>` are handled since those are what
  /// `$state`/`$props` commonly hold; anything else falls back to a plain
  /// (dynamic) index. [nullable] controls whether the cast allows (and the
  /// caller's constructor parameter expects) a missing/null value.
  String _extractExpr(String? type, String key, String source,
      {required bool nullable}) {
    final q = nullable ? '?' : '';
    switch (type) {
      case 'int':
      case 'double':
      case 'String':
      case 'bool':
        return "$source['$key'] as $type$q";
    }
    if (type != null) {
      final listMatch = RegExp(r'^List<(.+)>\??$').firstMatch(type);
      if (listMatch != null) {
        final list = "$source['$key'] as List$q";
        return nullable
            ? '($list)?.cast<${listMatch.group(1)}>()'
            : '($list).cast<${listMatch.group(1)}>()';
      }
      final mapMatch =
          RegExp(r'^Map<\s*String\s*,\s*(.+)>\??$').firstMatch(type);
      if (mapMatch != null) {
        final map = "$source['$key'] as Map$q";
        return nullable
            ? '($map)?.cast<String, ${mapMatch.group(1)}>()'
            : '($map).cast<String, ${mapMatch.group(1)}>()';
      }
    }
    return "$source['$key']";
  }

  /// `index`/`home` -> `/`; otherwise `/<filename>` (extension stripped) —
  /// mirroring file-based routing conventions like Next.js's `pages/`.
  String routeFor(AssetId asset) {
    final name = p.basenameWithoutExtension(asset.path);
    if (name == 'index' || name == 'home') return '/';
    return '/$name';
  }

  void _writeHeader(StringBuffer buf) {
    buf.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buf.writeln('// Regenerate with: dart run build_runner build');
    buf.writeln('// ignore_for_file: type=lint');
    buf.writeln();
  }
}

class PageRoute {
  final String path;
  final ComponentAnalyzerResult component;
  PageRoute(this.path, this.component);

  /// The registry key a route's component is registered/looked-up under —
  /// the route path with slashes stripped (`/` -> `index`, `/greeter` ->
  /// `greeter`), matching the filename `routeFor` derived it from.
  String get registryKey => path == '/' ? 'index' : path.substring(1);
}

/// The pieces of a `.clurit` file's analysis this builder needs: its
/// classified `@code` model, its generated class name, and the (relative,
/// POSIX-style) import paths from each output's directory to its compiled
/// client/server component.
class ComponentAnalyzerResult {
  final ComponentModel model;
  final String className;
  final String clientImportPath;
  final String serverImportPath;

  ComponentAnalyzerResult({
    required this.model,
    required this.className,
    required this.clientImportPath,
    required this.serverImportPath,
  });
}
