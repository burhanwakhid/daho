/// Stub declarations for Clurit's compile-time reactivity primitives.
///
/// `$state`, `$derived`, `$effect`, and `$props` are never actually invoked —
/// the build_runner generator (`clurit_generator.dart`) recognizes their call
/// shape inside `@code { }` blocks via `package:analyzer` and rewrites them
/// away entirely into real reactive fields, computed getters, effects, and
/// constructor parameters. These stubs exist only so an editor/analyzer
/// viewing `@code` content in isolation doesn't flag it as broken.
library;

/// Marks a reactive field: `var count = $state(0);`
T $state<T>(T initial) => initial;

/// Marks a computed value: `final doubled = $derived(count * 2);`, or, for
/// multi-statement derivations, `final x = $derived.by(() { ...; return v; });`.
const $derived = _DerivedMarker();

class _DerivedMarker {
  const _DerivedMarker();

  T call<T>(T value) => value;

  T by<T>(T Function() compute) => compute();
}

/// Marks a side effect that reruns after hydration and after any reactive
/// value it reads changes: `$effect(() { document.title = 'Count: $count'; });`
void $effect(void Function() fn) {}

/// Marks a value sourced from the component's initial render data:
/// `final title = $props<String>();`
T $props<T>([String? name]) => throw UnsupportedError(
  r'$props() is a compile-time marker resolved by the Clurit builder; '
  'it must not be called at runtime.',
);
