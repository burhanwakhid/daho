import 'package:test/test.dart';
import 'package:clurit/src/helpers.dart';

void main() {
  group('escapeHtml', () {
    test('escapes ampersand', () {
      expect(escapeHtml('a&b'), 'a&amp;b');
    });

    test('escapes less than', () {
      expect(escapeHtml('a<b'), 'a&lt;b');
    });

    test('escapes greater than', () {
      expect(escapeHtml('a>b'), 'a&gt;b');
    });

    test('escapes double quotes', () {
      expect(escapeHtml('a"b'), 'a&quot;b');
    });

    test('escapes single quotes', () {
      expect(escapeHtml("a'b"), 'a&#x27;b');
    });

    test('escapes multiple characters', () {
      expect(
        escapeHtml('<script>alert("xss")</script>'),
        '&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;',
      );
    });

    test('returns empty string for null', () {
      expect(escapeHtml(null), '');
    });

    test('converts non-string to string', () {
      expect(escapeHtml(42), '42');
      expect(escapeHtml(true), 'true');
    });

    test('handles empty string', () {
      expect(escapeHtml(''), '');
    });

    test('handles string without special characters', () {
      expect(escapeHtml('hello'), 'hello');
    });
  });

  group('stringify', () {
    test('returns empty string for null', () {
      expect(stringify(null), '');
    });

    test('returns string as-is', () {
      expect(stringify('hello'), 'hello');
    });

    test('converts bool to string', () {
      expect(stringify(true), 'true');
      expect(stringify(false), 'false');
    });

    test('converts num to string', () {
      expect(stringify(42), '42');
      expect(stringify(3.14), '3.14');
    });

    test('converts list to comma-separated string', () {
      expect(stringify([1, 2, 3]), '1, 2, 3');
    });

    test('converts map to string', () {
      final result = stringify({'key': 'value'});
      expect(result, contains('key'));
      expect(result, contains('value'));
    });
  });
}
