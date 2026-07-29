/// Token types produced by the lexer.
enum TokenType {
  text,
  echoEscaped,
  echoRaw,
  comment,
  directive,
  openTag,
  closeTag,
  sectionStart,
  sectionEnd,
  yieldTag,
  extendsTag,
  include,
  push,
  endPush,
  stack,
  verbatim,
  endVerbatim,
  code,
}

/// A token produced by the lexer.
class Token {
  final TokenType type;
  final String content;
  final String? args;

  Token(this.type, this.content, {this.args});
}

/// Lexer that tokenizes Clurit template source.
class Lexer {
  /// Tokenizes the template [source] into a list of tokens.
  static List<Token> tokenize(String source) {
    final tokens = <Token>[];
    int pos = 0;

    while (pos < source.length) {
      // 1. High-priority check for escaped echo @{{ ... }}
      if (source.startsWith('@{{', pos)) {
        final endIdx = source.indexOf('}}', pos + 3);
        if (endIdx != -1) {
          // Keep the {{ ... }} but drop the @
          tokens.add(Token(TokenType.text, source.substring(pos + 1, endIdx + 2)));
          pos = endIdx + 2;
          continue;
        }
      }

      // Check for comments
      if (source.startsWith('{{--', pos)) {
        final endIdx = source.indexOf('--}}', pos + 4);
        if (endIdx != -1) {
          tokens.add(
            Token(TokenType.comment, source.substring(pos + 4, endIdx)),
          );
          pos = endIdx + 4;
          continue;
        }
      }

      // Check for raw echo
      if (source.startsWith('{!!', pos)) {
        final endIdx = source.indexOf('!!}', pos + 3);
        if (endIdx != -1) {
          tokens.add(
            Token(TokenType.echoRaw, source.substring(pos + 3, endIdx).trim()),
          );
          pos = endIdx + 3;
          continue;
        }
      }

      // Check for escaped echo
      if (source.startsWith('{{', pos)) {
        final endIdx = source.indexOf('}}', pos + 2);
        if (endIdx != -1) {
          tokens.add(
            Token(
              TokenType.echoEscaped,
              source.substring(pos + 2, endIdx).trim(),
            ),
          );
          pos = endIdx + 2;
          continue;
        }
      }

      // Check for directives
      if (source[pos] == '@' && pos + 1 < source.length) {
        final match = RegExp(
          r'^@([a-zA-Z_][a-zA-Z0-9_]+)', // Use + to avoid matching empty keyword at @{{
        ).firstMatch(source.substring(pos));
        if (match != null) {
          final keyword = match.group(1)!;
          final fullMatch = match.group(0)!;

          // Handle escaped @@
          if (keyword == '@') {
            tokens.add(Token(TokenType.text, '@'));
            pos += 2;
            continue;
          }

          // Handle @code { ... } with brace matching
          if (keyword == 'code') {
            int openBrace = source.indexOf('{', pos + fullMatch.length);
            if (openBrace != -1) {
              int closeBrace = _findClosingBrace(source, openBrace);
              if (closeBrace != -1) {
                final codeContent = source.substring(openBrace + 1, closeBrace);
                tokens.add(Token(TokenType.code, codeContent));
                pos = closeBrace + 1;
                continue;
              }
            }
          }

          // Handle @(...) for expressions/lambdas
          if (keyword.isEmpty && source[pos] == '@' && pos + 1 < source.length && source[pos + 1] == '(') {
            int closeParen = _findClosingParen(source, pos + 1);
            if (closeParen != -1) {
              final expression = source.substring(pos + 2, closeParen);
              tokens.add(Token(TokenType.echoEscaped, expression)); // Reuse echoEscaped for now
              pos = closeParen + 1;
              continue;
            }
          }

          // Parse optional arguments
          String? args;
          int endPos = pos + fullMatch.length;
          if (endPos < source.length && source[endPos] == '(') {
            final argsEnd = _findClosingParen(source, endPos);
            if (argsEnd != -1) {
              args = source.substring(endPos + 1, argsEnd);
              endPos = argsEnd + 1;
            }
          }

          final tokenType = _mapKeyword(keyword);
          tokens.add(Token(tokenType, keyword, args: args));
          pos = endPos;
          continue;
        }
      }

      // Plain text
      int nextSpecial = source.length;
      for (final pattern in ['{{', '{!!', '{{--', '@']) {
        final idx = source.indexOf(pattern, pos + 1);
        if (idx != -1 && idx < nextSpecial) {
          nextSpecial = idx;
        }
      }

      if (nextSpecial > pos) {
        tokens.add(Token(TokenType.text, source.substring(pos, nextSpecial)));
        pos = nextSpecial;
      } else {
        tokens.add(Token(TokenType.text, source[pos]));
        pos++;
      }
    }

    return tokens;
  }

  static TokenType _mapKeyword(String keyword) {
    switch (keyword) {
      case 'if':
      case 'elseif':
      case 'unless':
      case 'for':
      case 'foreach':
      case 'while':
      case 'component':
      case 'slot':
      case 'else':
        return TokenType.openTag;
      case 'endif':
      case 'endunless':
      case 'endfor':
      case 'endforeach':
      case 'endwhile':
      case 'endcomponent':
      case 'endslot':
        return TokenType.closeTag;
      case 'section':
        return TokenType.sectionStart;
      case 'endsection':
        return TokenType.sectionEnd;
      case 'yield':
        return TokenType.yieldTag;
      case 'extends':
        return TokenType.extendsTag;
      case 'include':
      case 'includeIf':
      case 'includeFirst':
        return TokenType.include;
      case 'push':
        return TokenType.push;
      case 'endpush':
        return TokenType.endPush;
      case 'stack':
        return TokenType.stack;
      case 'verbatim':
        return TokenType.verbatim;
      case 'endverbatim':
        return TokenType.endVerbatim;
      case 'code':
        return TokenType.code;
      default:
        return TokenType.directive;
    }
  }

  static int _findClosingParen(String source, int openPos) {
    int depth = 0;
    for (int i = openPos; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static int _findClosingBrace(String source, int openPos) {
    int depth = 0;
    for (int i = openPos; i < source.length; i++) {
      if (source[i] == '{') depth++;
      if (source[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}
