import 'compiler.dart';

/// In-memory cache of compiled templates (the AST, not the rendered
/// output — a template's rendered HTML depends on per-request data, so
/// caching the render result would return stale content for every request
/// after the first one whenever [debug] is false; see the reported bug
/// this replaced).
///
/// [cachePath] is accepted for backward API compatibility but currently
/// unused: the previous file-based invalidation compared a cache file's
/// timestamp against a `$key.source` file that nothing ever wrote, so it
/// never actually invalidated anything.
class TemplateCache {
  final String? cachePath;
  final bool debug;
  final Map<String, ParsedTemplate> _memoryCache = {};

  TemplateCache({this.cachePath, this.debug = false});

  /// Gets a cached compiled template, or null if not cached (or [debug]).
  ParsedTemplate? get(String key) {
    if (debug) return null; // Always recompile in debug mode
    return _memoryCache[key];
  }

  /// Stores a compiled template in cache.
  void set(String key, ParsedTemplate template) {
    _memoryCache[key] = template;
  }

  /// Clears the cache.
  void clear() {
    _memoryCache.clear();
  }
}
