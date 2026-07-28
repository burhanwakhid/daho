/// Template context that holds data and provides helper methods.
class TemplateContext {
  final Map<String, dynamic> _data;

  TemplateContext(Map<String, dynamic>? data) : _data = data ?? {};

  /// Gets a value from the context.
  dynamic get(String key) => _data[key];

  /// Sets a value in the context.
  void set(String key, dynamic value) => _data[key] = value;

  /// Merges additional data into the context.
  void merge(Map<String, dynamic> data) => _data.addAll(data);

  /// Gets all data as a map.
  Map<String, dynamic> toMap() => Map.unmodifiable(_data);

  /// Checks if a key exists.
  bool has(String key) => _data.containsKey(key);
}
