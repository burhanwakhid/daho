import 'node.dart';

/// A `@yield('name')` placeholder in a layout template.
///
/// Resolved lazily at render time by looking up [name] in the section map
/// stashed under [sectionsContextKey] in the context (see
/// `CluritEngine._handleExtends`) — never at parse time, since the actual
/// section content (and the data it depends on) isn't known until a child
/// template is rendered against real request data.
class YieldNode extends Node {
  final String name;
  YieldNode(this.name);

  /// Context key under which the child template's `@section` nodes are
  /// stashed (a `Map<String, Node>`) when rendering a layout it extends.
  static const sectionsContextKey = '__clurit_sections__';

  @override
  String compile(Map<String, dynamic> context) {
    final sections = context[sectionsContextKey] as Map<String, Node>?;
    final section = sections?[name];
    if (section == null) return '';
    return section.compile(context);
  }
}
