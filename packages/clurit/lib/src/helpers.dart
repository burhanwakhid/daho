/// HTML escaping and string utilities for Clurit.
library;

/// Escapes HTML special characters to prevent XSS.
String escapeHtml(dynamic value) {
  if (value == null) return '';
  final str = value.toString();
  return str
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

/// Converts a Dart expression result to a string for output.
String stringify(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  if (value is List) return value.join(', ');
  if (value is Map) return value.toString();
  return value.toString();
}
