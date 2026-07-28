import 'dart:io';
import 'package:path/path.dart' as p;
import 'lexer.dart';
import 'parser.dart';
import 'nodes/node.dart';

/// The result of compiling a template: its AST, the layout it `@extends`
/// (if any), its `@section` bodies keyed by name (for a layout to
/// `@yield` from), and its `@push` bodies keyed by stack name (for a
/// layout to `@stack` from).
class ParsedTemplate {
  final List<Node> nodes;
  final String? extendsLayout;
  final Map<String, Node> sections;
  final Map<String, List<Node>> pushes;

  ParsedTemplate({
    required this.nodes,
    required this.extendsLayout,
    required this.sections,
    required this.pushes,
  });
}

/// Template compiler that converts Clurit template source to an AST.
class Compiler {
  final String viewsPath;
  final Node Function(String template, Map<String, dynamic>? data)
  includeResolver;

  Compiler({required this.viewsPath, required this.includeResolver});

  /// Compiles a template file to an AST.
  ParsedTemplate compileFile(String templatePath) {
    final fullPath = p.join(viewsPath, '$templatePath.clurit');
    final file = File(fullPath);

    if (!file.existsSync()) {
      throw FileSystemException('Template not found', fullPath);
    }

    final source = file.readAsStringSync();
    return compileSource(source);
  }

  /// Compiles template source text to an AST.
  ParsedTemplate compileSource(String source) {
    final tokens = Lexer.tokenize(source);
    final parser = Parser(tokens, includeResolver: includeResolver);
    final nodes = parser.parse();
    return ParsedTemplate(
      nodes: nodes,
      extendsLayout: parser.extendsLayout,
      sections: parser.sections,
      pushes: parser.pushes,
    );
  }

  /// Compiles a template and returns the rendered HTML.
  String compileAndRender(String templatePath, Map<String, dynamic> context) {
    final template = compileFile(templatePath);
    final buf = StringBuffer();
    for (final node in template.nodes) {
      buf.write(node.compile(context));
    }
    return buf.toString();
  }
}
