## 0.1.0+1

- `configureClurit(components: ...)` — bulk-register the generated
  `clurit_components.g.dart` factory registry in one call, removing
  hand-written `app.registerComponent(...)` boilerplate per page.
- `res.view(name, data: {...})` now works transparently for `@code`-bearing
  (reactive) templates, not just plain Blade templates.

## 0.1.0

- Initial release.
- Daho integration for Clurit template engine.
- `app.configureClurit(viewsPath: 'views')` — setup engine.
- `res.view('template', {'key': 'value'})` — render template.
