import 'lexer.dart';
import 'nodes/node.dart';
import 'nodes/text_node.dart';
import 'nodes/echo_node.dart';
import 'nodes/if_node.dart';
import 'nodes/foreach_node.dart';
import 'nodes/include_node.dart';
import 'nodes/component_node.dart';
import 'nodes/yield_node.dart';
import 'nodes/stack_node.dart';
import 'nodes/code_node.dart';

/// A node holding a list of body nodes whose compilation is deferred to
/// render time, used for `@section`/`@push` bodies. Compiling those bodies
/// eagerly (with whatever context happens to be at hand while parsing —
/// none) would bake the section's HTML in before any real request data
/// exists; wrapping them in a node instead lets them compile normally
/// against the real context when the tree is actually rendered.
class DeferredBodyNode extends Node {
  final List<Node> body;
  DeferredBodyNode(this.body);

  @override
  String compile(Map<String, dynamic> context) {
    final buf = StringBuffer();
    for (final node in body) {
      buf.write(node.compile(context));
    }
    return buf.toString();
  }
}

/// Parser that converts tokens into an AST of nodes.
class Parser {
  final List<Token> tokens;
  final Node Function(String template, Map<String, dynamic>? data)
  includeResolver;
  int _pos = 0;
  bool _insideSection = false;

  /// The layout named by `@extends('...')`, if any.
  String? extendsLayout;

  /// `@section` bodies keyed by name, for a layout's `@yield('name')` to
  /// pull from when this template extends one.
  final Map<String, Node> sections = {};

  /// `@push` bodies keyed by stack name, in registration order, for a
  /// layout's `@stack('name')` to pull from when this template extends
  /// one. A stack may be pushed to more than once.
  final Map<String, List<Node>> pushes = {};

  Parser(this.tokens, {required this.includeResolver});

  /// Parses the tokens into a list of AST nodes.
  List<Node> parse() {
    final nodes = <Node>[];
    while (_pos < tokens.length) {
      final node = _parseNode();
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  Node? _parseNode() {
    if (_pos >= tokens.length) return null;

    final token = tokens[_pos];

    switch (token.type) {
      case TokenType.text:
        _pos++;
        return TextNode(token.content);

      case TokenType.echoEscaped:
        _pos++;
        return EchoNode(token.content, escaped: true);

      case TokenType.echoRaw:
        _pos++;
        return EchoNode(token.content, escaped: false);

      case TokenType.comment:
        _pos++;
        return null;

      case TokenType.openTag:
        return _parseOpenTag(token);

      case TokenType.closeTag:
        _pos++;
        return null;

      case TokenType.sectionStart:
        _pos++;
        if (_insideSection) {
          // Don't parse nested sections recursively, just return null
          return null;
        }
        return _parseSection(token);

      case TokenType.sectionEnd:
        _pos++;
        return null;

      case TokenType.extendsTag:
        extendsLayout = _extractString(token.args ?? '');
        _pos++;
        return null;

      case TokenType.include:
        _pos++;
        return _parseInclude(token);

      case TokenType.yieldTag:
        _pos++;
        return _parseYield(token);

      case TokenType.push:
        _pos++;
        return _parsePush(token);

      case TokenType.endPush:
        _pos++;
        return null;

      case TokenType.stack:
        _pos++;
        return StackNode(_extractString(token.args ?? ''));

      case TokenType.verbatim:
        return _parseVerbatim();

      case TokenType.code:
        return _parseCodeBlock();

      case TokenType.endVerbatim:
        _pos++;
        return null;

      default:
        _pos++;
        return TextNode('@${token.content}');
    }
  }

  Node? _parseOpenTag(Token token) {
    _pos++;

    switch (token.content) {
      case 'if':
      case 'elseif':
      case 'unless':
        return _parseIf(token);

      case 'else':
        return null;

      case 'foreach':
        return _parseForeach(token);

      case 'for':
        return _parseFor(token);

      case 'while':
        return _parseWhile(token);

      case 'component':
        return _parseComponent(token);

      case 'slot':
        return null;

      default:
        return null;
    }
  }

  Node _parseIf(Token token) {
    final condition = token.args ?? '';
    final thenBody = <Node>[];
    final elseBody = <Node>[];

    while (_pos < tokens.length) {
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.openTag &&
          (tokens[_pos].content == 'else' ||
              tokens[_pos].content == 'elseif')) {
        break;
      }
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endif') {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) thenBody.add(node);
    }

    if (_pos < tokens.length && tokens[_pos].type == TokenType.openTag) {
      if (tokens[_pos].content == 'else') {
        _pos++;
        while (_pos < tokens.length) {
          if (_pos < tokens.length &&
              tokens[_pos].type == TokenType.closeTag &&
              tokens[_pos].content == 'endif') {
            _pos++;
            break;
          }
          final node = _parseNode();
          if (node != null) elseBody.add(node);
        }
      } else if (tokens[_pos].content == 'elseif') {
        final elseIfToken = tokens[_pos];
        _pos++;
        elseBody.add(_parseIf(elseIfToken));
      }
    }

    return IfNode(
      condition: condition,
      thenBody: thenBody,
      elseBody: elseBody.isNotEmpty ? elseBody : null,
    );
  }

  Node _parseForeach(Token token) {
    final args = token.args ?? '';
    final asIdx = args.indexOf(' as ');
    if (asIdx == -1) {
      return TextNode('');
    }

    final iterable = args.substring(0, asIdx).trim();
    final varPart = args.substring(asIdx + 4).trim();

    String? key;
    String variable;
    if (varPart.contains('=>')) {
      final parts = varPart.split('=>');
      key = parts[0].trim().replaceAll('\$', '');
      variable = parts[1].trim().replaceAll('\$', '');
    } else {
      variable = varPart.replaceAll('\$', '');
    }

    final body = <Node>[];
    while (_pos < tokens.length) {
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endforeach') {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) body.add(node);
    }

    return ForeachNode(
      iterableExpr: iterable,
      variable: variable,
      key: key,
      body: body,
    );
  }

  Node _parseFor(Token token) {
    final body = <Node>[];
    while (_pos < tokens.length) {
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endfor') {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) body.add(node);
    }
    return ForeachNode(iterableExpr: '[]', variable: 'i', body: body);
  }

  Node _parseWhile(Token token) {
    final condition = token.args ?? '';
    final body = <Node>[];
    while (_pos < tokens.length) {
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endwhile') {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) body.add(node);
    }
    return IfNode(condition: condition, thenBody: body);
  }

  Node _parseComponent(Token token) {
    final template = _extractString(token.args ?? '');
    final data = <String, dynamic>{};
    final slots = <String, List<Node>>{};

    final defaultBody = <Node>[];
    String? currentSlot;

    while (_pos < tokens.length) {
      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endcomponent') {
        _pos++;
        break;
      }

      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.openTag &&
          tokens[_pos].content == 'slot') {
        currentSlot = _extractString(tokens[_pos].args ?? '');
        _pos++;
        continue;
      }

      if (_pos < tokens.length &&
          tokens[_pos].type == TokenType.closeTag &&
          tokens[_pos].content == 'endslot') {
        currentSlot = null;
        _pos++;
        continue;
      }

      final node = _parseNode();
      if (node != null) {
        if (currentSlot != null) {
          slots.putIfAbsent(currentSlot, () => []);
          slots[currentSlot]!.add(node);
        } else {
          defaultBody.add(node);
        }
      }
    }

    if (defaultBody.isNotEmpty) {
      slots['default'] = defaultBody;
    }

    return ComponentNode(
      template: template,
      data: data,
      slots: slots,
      resolver: includeResolver,
    );
  }

  Node _parseInclude(Token token) {
    final template = _extractString(token.args ?? '');
    return IncludeNode(template: template, resolver: includeResolver);
  }

  Node _parseYield(Token token) {
    return YieldNode(_extractString(token.args ?? ''));
  }

  Node _parseSection(Token token) {
    _insideSection = true;
    final body = <Node>[];

    while (_pos < tokens.length) {
      if (_pos < tokens.length && tokens[_pos].type == TokenType.sectionEnd) {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) body.add(node);
    }

    _insideSection = false;

    final sectionNode = DeferredBodyNode(body);
    final name = _extractString(token.args ?? '');
    if (name.isNotEmpty) sections[name] = sectionNode;
    return sectionNode;
  }

  Node _parsePush(Token token) {
    final body = <Node>[];
    while (_pos < tokens.length) {
      if (_pos < tokens.length && tokens[_pos].type == TokenType.endPush) {
        _pos++;
        break;
      }
      final node = _parseNode();
      if (node != null) body.add(node);
    }
    final pushNode = DeferredBodyNode(body);
    final name = _extractString(token.args ?? '');
    if (name.isNotEmpty) {
      pushes.putIfAbsent(name, () => []).add(pushNode);
    }
    return pushNode;
  }

  Node _parseVerbatim() {
    final buf = StringBuffer();
    while (_pos < tokens.length) {
      if (tokens[_pos].type == TokenType.endVerbatim) {
        _pos++;
        break;
      }
      buf.write(tokens[_pos].content);
      _pos++;
    }
    return TextNode(buf.toString());
  }

  Node _parseCodeBlock() {
    final token = tokens[_pos];
    _pos++;
    return CodeNode(token.content.trim());
  }

  String _extractString(String args) {
    final trimmed = args.trim();
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
        (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }
}
