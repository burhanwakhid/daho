import 'package:test/test.dart';
import 'package:clurit/src/lexer.dart';

void main() {
  group('Lexer', () {
    group('tokenize', () {
      test('plain text', () {
        final tokens = Lexer.tokenize('Hello, World!');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.text);
        expect(tokens[0].content, 'Hello, World!');
      });

      test('escaped echo', () {
        final tokens = Lexer.tokenize('{{ \$name }}');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.echoEscaped);
        expect(tokens[0].content, '\$name');
      });

      test('raw echo', () {
        final tokens = Lexer.tokenize('{!! \$html !!}');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.echoRaw);
        expect(tokens[0].content, '\$html');
      });

      test('comment', () {
        final tokens = Lexer.tokenize('{{-- This is a comment --}}');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.comment);
        expect(tokens[0].content, ' This is a comment ');
      });

      test('if directive', () {
        final tokens = Lexer.tokenize('@if(\$user != null)');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.openTag);
        expect(tokens[0].content, 'if');
        expect(tokens[0].args, '\$user != null');
      });

      test('endif directive', () {
        final tokens = Lexer.tokenize('@endif');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.closeTag);
        expect(tokens[0].content, 'endif');
      });

      test('foreach directive', () {
        final tokens = Lexer.tokenize('@foreach(\$items as \$item)');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.openTag);
        expect(tokens[0].content, 'foreach');
        expect(tokens[0].args, '\$items as \$item');
      });

      test('include directive', () {
        final tokens = Lexer.tokenize("@include('partials.header')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.include);
        expect(tokens[0].content, 'include');
        expect(tokens[0].args, "'partials.header'");
      });

      test('extends directive', () {
        final tokens = Lexer.tokenize("@extends('layouts.main')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.extendsTag);
        expect(tokens[0].content, 'extends');
      });

      test('section directive', () {
        final tokens = Lexer.tokenize("@section('content')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.sectionStart);
        expect(tokens[0].content, 'section');
      });

      test('endsection directive', () {
        final tokens = Lexer.tokenize('@endsection');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.sectionEnd);
        expect(tokens[0].content, 'endsection');
      });

      test('yield directive', () {
        final tokens = Lexer.tokenize("@yield('content')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.yieldTag);
        expect(tokens[0].content, 'yield');
      });

      test('push directive', () {
        final tokens = Lexer.tokenize("@push('scripts')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.push);
        expect(tokens[0].content, 'push');
      });

      test('endpush directive', () {
        final tokens = Lexer.tokenize('@endpush');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.endPush);
        expect(tokens[0].content, 'endpush');
      });

      test('stack directive', () {
        final tokens = Lexer.tokenize("@stack('scripts')");
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.stack);
        expect(tokens[0].content, 'stack');
      });

      test('verbatim directive', () {
        final tokens = Lexer.tokenize('@verbatim');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.verbatim);
        expect(tokens[0].content, 'verbatim');
      });

      test('endverbatim directive', () {
        final tokens = Lexer.tokenize('@endverbatim');
        expect(tokens.length, 1);
        expect(tokens[0].type, TokenType.endVerbatim);
        expect(tokens[0].content, 'endverbatim');
      });

      test('mixed content', () {
        final source = '<h1>{{ \$title }}</h1><p>{!! \$content !!}</p>';
        final tokens = Lexer.tokenize(source);
        expect(tokens.length, 5);
        expect(tokens[0].type, TokenType.text);
        expect(tokens[0].content, '<h1>');
        expect(tokens[1].type, TokenType.echoEscaped);
        expect(tokens[1].content, '\$title');
        expect(tokens[2].type, TokenType.text);
        expect(tokens[2].content, '</h1><p>');
        expect(tokens[3].type, TokenType.echoRaw);
        expect(tokens[3].content, '\$content');
        expect(tokens[4].type, TokenType.text);
        expect(tokens[4].content, '</p>');
      });

      test('template with multiple directives', () {
        final source = '''
@if(\$show)
  @foreach(\$items as \$item)
    <p>{{ \$item }}</p>
  @endforeach
@endif
''';
        final tokens = Lexer.tokenize(source);
        expect(
          tokens.any((t) => t.type == TokenType.openTag && t.content == 'if'),
          isTrue,
        );
        expect(
          tokens.any(
            (t) => t.type == TokenType.openTag && t.content == 'foreach',
          ),
          isTrue,
        );
        expect(tokens.any((t) => t.type == TokenType.echoEscaped), isTrue);
        expect(
          tokens.any(
            (t) => t.type == TokenType.closeTag && t.content == 'endforeach',
          ),
          isTrue,
        );
        expect(
          tokens.any(
            (t) => t.type == TokenType.closeTag && t.content == 'endif',
          ),
          isTrue,
        );
      });
    });
  });
}
