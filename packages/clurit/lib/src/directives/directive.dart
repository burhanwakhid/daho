/// Abstract interface for custom Clurit directives.
abstract class Directive {
  /// The directive name (without @).
  String get name;

  /// Compiles the directive with the given arguments and context.
  String compile(List<String> args, Map<String, dynamic> context);
}
