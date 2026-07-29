import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// A client-side router for Clurit that enables SPA-like navigation while
/// maintaining SSR compatibility. Since each page constructs and hydrates
/// its own generated `CluritComponent` subclass, the router doesn't know
/// which component a newly-loaded page needs — [onHydrate] is called with
/// the freshly-swapped-in content root so the app's own bootstrap (which
/// does know) can construct and hydrate the right component for it.
class CluritRouter {
  final void Function(web.Element root) onHydrate;
  final String contentSelector;

  CluritRouter({required this.onHydrate, this.contentSelector = 'main'});

  void init() {
    // Intercept clicks on anchor tags
    web.document.body?.addEventListener(
      'click',
      (web.MouseEvent event) {
        final target = event.target as web.HTMLElement?;
        final anchor = _findAnchor(target);

        if (anchor != null) {
          final href = anchor.getAttribute('href');
          if (href != null && _isLocal(href)) {
            event.preventDefault();
            navigateTo(href);
          }
        }
      }.toJS,
    );

    // Handle back/forward buttons
    web.window.onpopstate = (web.PopStateEvent event) {
      _loadPage(web.window.location.pathname, pushState: false);
    }.toJS;
  }

  void navigateTo(String path) {
    _loadPage(path, pushState: true);
  }

  Future<void> _loadPage(String path, {bool pushState = true}) async {
    try {
      // 1. Fetch the page
      final response = await web.window.fetch(path.toJS).toDart;
      if (!response.ok) {
        throw Exception('Failed to load page');
      }

      final html = await response.text().toDart;

      // 2. Parse and update content
      final parser = web.DOMParser();
      final doc = parser.parseFromString(html, 'text/html');
      final newContent = doc.querySelector(contentSelector) as web.HTMLElement?;
      final currentContent =
          web.document.querySelector(contentSelector) as web.HTMLElement?;

      if (newContent != null && currentContent != null) {
        currentContent.innerHTML = newContent.innerHTML;

        // Update Title
        if (doc.title.isNotEmpty) {
          web.document.title = doc.title;
        }

        // 3. Update State (if a new state script is present in the fetched HTML)
        final newStateScript = doc.getElementById('clurit-state');
        if (newStateScript != null) {
          final stateElement = web.document.getElementById('clurit-state');
          if (stateElement != null) {
            stateElement.textContent = newStateScript.textContent;
          }
        }

        // 4. Update URL
        if (pushState) {
          web.window.history.pushState(null, '', path);
        }

        // 5. Re-hydrate the new content root
        onHydrate(currentContent);
      }
    } catch (e) {
      web.console.error('Clurit Router Error: $e'.toJS);
      // Fallback: full page reload
      if (pushState) {
        web.window.location.assign(path);
      }
    }
  }

  web.HTMLAnchorElement? _findAnchor(web.HTMLElement? el) {
    if (el == null) {
      return null;
    }
    if (el.isA<web.HTMLAnchorElement>()) {
      return el as web.HTMLAnchorElement;
    }
    return _findAnchor(el.parentElement as web.HTMLElement?);
  }

  bool _isLocal(String href) {
    return href.startsWith('/') && !href.startsWith('//');
  }
}
