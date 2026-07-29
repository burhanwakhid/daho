// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;

import '../views/index.clurit.client.dart' deferred as _page0;
import '../views/greeter.clurit.client.dart' deferred as _page1;
import '../views/posts.clurit.client.dart' deferred as _page2;

Future<void> hydrateCurrentPage(web.Element root) async {
  final state = readInitialState();
  switch (web.window.location.pathname) {
    case '/greeter':
      await _page1.loadLibrary();
      _page1.GreeterComponentClient(greetIndex: state['greetIndex'] as int?)
          .hydrate(root);
      break;
    case '/posts':
      await _page2.loadLibrary();
      _page2.PostsComponentClient(
              loading: state['loading'] as bool?,
              errorMessage: state['errorMessage'],
              posts: (state['posts'] as List?)?.cast<Map<String, dynamic>>())
          .hydrate(root);
      break;
    default:
      await _page0.loadLibrary();
      _page0.IndexComponentClient(
              counter: state['counter'] as int?,
              items: (state['items'] as List?)?.cast<String>(),
              name: state['name'] as String?,
              message: state['message'] as String)
          .hydrate(root);
      break;
  }
}

void main() {
  final root = web.document.querySelector('#app');
  if (root == null) return;
  hydrateCurrentPage(root);
  CluritRouter(
    onHydrate: hydrateCurrentPage,
    contentSelector: '#app',
  ).init();
}
