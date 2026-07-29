import 'dart:convert';
import 'node.dart';

/// A node representing a @code block in Clurit.
/// It contains Dart code that should be executed or hydrated on the client.
class CodeNode extends Node {
  final String code;

  CodeNode(this.code);

  @override
  String compile(Map<String, dynamic> context) {
    // For SSR, we embed the initial state as JSON for hydration.
    // We only want to render this script tag once per page.
    if (context['__clurit_state_rendered'] == true) {
      return '<!-- @code block (state already injected) -->';
    }
    context['__clurit_state_rendered'] = true;

    final state = context['state'] ?? {};
    final jsonState = jsonEncode(state);

    return '''
<script id="clurit-state" type="application/json">
  $jsonState
</script>
<!-- @code block logic -->
''';
  }
}
