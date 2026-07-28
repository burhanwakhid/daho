import 'dart:io';
import 'package:path/path.dart' as p;
import 'compiler.dart';
import 'cache.dart';
import 'renderer.dart';
import 'nodes/node.dart';
import 'nodes/yield_node.dart';
import 'nodes/stack_node.dart';
import 'directives/directive.dart';
import 'directives/core_directives.dart';

/// The main Clurit template engine.
///
/// Manages template compilation, caching, and rendering.
class CluritEngine {
  /// Global instance accessible from extensions.
  static CluritEngine? instance;

  final String viewsPath;
  final TemplateCache _cache;
  final Compiler _compiler;
  final Map<String, Directive> _directives = {};

  CluritEngine({
    required this.viewsPath,
    String? cachePath,
    bool debug = false,
  })  : _cache = TemplateCache(cachePath: cachePath, debug: debug),
        _compiler = Compiler(
          viewsPath: viewsPath,
          includeResolver: _createResolver(viewsPath),
        ) {
    // Register core directives
    _directives.addAll(CoreDirectives.all());
  }

  /// Renders a template with the given data.
  String render(String template, [Map<String, dynamic>? data]) {
    final context = data ?? {};
    return _renderTemplate(_compileCached(template), context);
  }

  /// Renders a template from source string.
  String renderSource(String source, [Map<String, dynamic>? data]) {
    final context = data ?? {};
    return _renderTemplate(_compiler.compileSource(source), context);
  }

  /// Compiles [name], going through the cache (a no-op cache in debug mode).
  ParsedTemplate _compileCached(String name) {
    final cached = _cache.get(name);
    if (cached != null) return cached;
    final parsed = _compiler.compileFile(name);
    _cache.set(name, parsed);
    return parsed;
  }

  /// Renders [template]. If it `@extends` a layout, the layout is rendered
  /// instead, with the child's `@section` bodies made available to the
  /// layout's `@yield` calls (see [YieldNode]) and its `@push` bodies made
  /// available to the layout's `@stack` calls (see [StackNode]) — nested
  /// `@extends` (a layout that itself extends another layout) isn't
  /// supported.
  String _renderTemplate(ParsedTemplate template, Map<String, dynamic> context) {
    final layoutName = template.extendsLayout;
    if (layoutName == null) {
      return Renderer.render(template.nodes, context);
    }
    // @extends('layouts.main') uses Blade-style dot namespacing, same as
    // @include — Compiler.compileFile itself doesn't do this conversion
    // (top-level render() calls pass slash-style paths directly).
    final layout = _compileCached(layoutName.replaceAll('.', p.separator));
    final layoutContext = <String, dynamic>{
      ...context,
      YieldNode.sectionsContextKey: template.sections,
      StackNode.stacksContextKey: template.pushes,
    };
    return Renderer.render(layout.nodes, layoutContext);
  }

  /// Registers a custom directive.
  void directive(String name, Directive handler) {
    _directives[name] = handler;
  }

  /// Registers a custom directive as a function.
  void directiveFn(String name, String Function(List<String> args, Map<String, dynamic> context) handler) {
    _directives[name] = _FunctionDirective(name, handler);
  }

  /// Clears the template cache.
  void clearCache() => _cache.clear();

  static Node Function(String, Map<String, dynamic>?) _createResolver(String viewsPath) {
    return (template, data) {
      final relativePath = template.replaceAll('.', p.separator);
      final fullPath = p.join(viewsPath, '$relativePath.clurit');
      final file = File(fullPath);
      if (!file.existsSync()) {
        throw FileSystemException('Template not found', fullPath);
      }
      final source = file.readAsStringSync();
      // Return a proxy node that compiles the included template
      return _TemplateProxyNode(source, data);
    };
  }
}

/// A proxy node that compiles an included template.
class _TemplateProxyNode extends Node {
  final String source;
  final Map<String, dynamic>? data;

  _TemplateProxyNode(this.source, this.data);

  @override
  String compile(Map<String, dynamic> context) {
    final mergedContext = Map<String, dynamic>.from(context);
    if (data != null) mergedContext.addAll(data!);

    // Use a simple regex-based renderer for included templates
    // In production, this would use the full compiler
    return _simpleRender(source, mergedContext);
  }

  String _simpleRender(String source, Map<String, dynamic> context) {
    var result = source;

    // Replace {{ expr }} with values
    result = result.replaceAllMapped(
      RegExp(r'\{\{\s*(.+?)\s*\}\}'),
      (match) {
        final expr = match.group(1)!;
        final value = _evaluateSimple(expr, context);
        return _escapeHtml(value?.toString() ?? '');
      },
    );

    // Replace {!! expr !!} with raw values
    result = result.replaceAllMapped(
      RegExp(r'\{!!\s*(.+?)\s*!!\}'),
      (match) {
        final expr = match.group(1)!;
        final value = _evaluateSimple(expr, context);
        return value?.toString() ?? '';
      },
    );

    return result;
  }

  dynamic _evaluateSimple(String expr, Map<String, dynamic> context) {
    final trimmed = expr.trim();
    if (trimmed.startsWith('\$')) {
      final varName = trimmed.substring(1);
      return context[varName];
    }
    return context[trimmed];
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }
}

/// A directive implemented as a function.
class _FunctionDirective implements Directive {
  @override
  final String name;
  final String Function(List<String> args, Map<String, dynamic> context) handler;

  _FunctionDirective(this.name, this.handler);

  @override
  String compile(List<String> args, Map<String, dynamic> context) {
    return handler(args, context);
  }
}
