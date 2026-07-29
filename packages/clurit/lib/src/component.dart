import 'dart:async';

/// Base class for generated Clurit interactive components.
///
/// A `.clurit` file with an `@code { }` block generates a subclass of this
/// implementing [renderInitial] and [initialStateJson] from the same parse
/// pass, so server output and client hydration can never drift out of sync.
///
/// [registerUpdater]/[markDirty] implement the dependency-driven update
/// scheduling shared by DOM bindings and `$effect`s: client hydration code
/// (in a generated `*.clurit.client.dart` subclass) registers one closure
/// per binding against the state field(s) it reads, and a reactive field's
/// setter calls [markDirty] with its own name whenever it changes. Nothing
/// on this base class touches the DOM or imports `package:web` — the
/// server can construct and call [renderInitial] on any generated component
/// without pulling in a browser-only dependency.
abstract class CluritComponent {
  /// Renders the component's initial server-side HTML, with stable
  /// anchor-comment markers (`<!--cl:N-->`, `<!--cl-if:N-->`,
  /// `<!--cl-for:N-->`) baked in at every binding site.
  String renderInitial();

  /// The initial reactive state, serialized for client hydration via the
  /// `<script id="clurit-state">` tag.
  Map<String, dynamic> initialStateJson();

  final Map<String, List<void Function()>> _updaters = {};
  final Set<void Function()> _dirty = {};
  bool _flushScheduled = false;

  /// Registers [apply] to run (at most once per microtask flush) whenever
  /// [field] changes. Called during client hydration, once per binding —
  /// never re-queried or re-registered afterward.
  void registerUpdater(String field, void Function() apply) {
    _updaters.putIfAbsent(field, () => []).add(apply);
  }

  /// Called by a generated reactive field's setter whenever it changes.
  /// A no-op on the server (nothing registers updaters there, since
  /// [renderInitial] reads fields directly rather than through bindings).
  void markDirty(String field) {
    final appliers = _updaters[field];
    if (appliers == null || appliers.isEmpty) return;
    _dirty.addAll(appliers);
    if (_flushScheduled) return;
    _flushScheduled = true;
    Timer(Duration.zero, () {
      _flushScheduled = false;
      final toRun = _dirty.toList();
      _dirty.clear();
      for (final apply in toRun) {
        apply();
      }
    });
  }
}
