import 'directive.dart';
import '../helpers.dart';

/// Core built-in directives for Clurit.
class CoreDirectives {
  /// Creates a map of all core directives.
  static Map<String, Directive> all() {
    return {
      'csrf': _CsrfDirective(),
      'method': _MethodDirective(),
      'raw': _RawDirective(),
      'json': _JsonDirective(),
    };
  }
}

/// @csrf — outputs a CSRF hidden input (placeholder).
class _CsrfDirective implements Directive {
  @override
  String get name => 'csrf';

  @override
  String compile(List<String> args, Map<String, dynamic> context) {
    final token = context['_csrf_token'] ?? '';
    return '<input type="hidden" name="_token" value="${escapeHtml(token)}">';
  }
}

/// @method — outputs a method override hidden input.
class _MethodDirective implements Directive {
  @override
  String get name => 'method';

  @override
  String compile(List<String> args, Map<String, dynamic> context) {
    final method = args.isNotEmpty ? args[0].toUpperCase() : 'POST';
    return '<input type="hidden" name="_method" value="$method">';
  }
}

/// @raw — outputs content without processing.
class _RawDirective implements Directive {
  @override
  String get name => 'raw';

  @override
  String compile(List<String> args, Map<String, dynamic> context) {
    return args.join(' ');
  }
}

/// @json — outputs a value as JSON.
class _JsonDirective implements Directive {
  @override
  String get name => 'json';

  @override
  String compile(List<String> args, Map<String, dynamic> context) {
    if (args.isEmpty) return '';
    final key = args[0].replaceAll('\$', '');
    final value = context[key];
    return value?.toString() ?? 'null';
  }
}
