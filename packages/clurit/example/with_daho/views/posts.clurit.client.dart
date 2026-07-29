// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'dart:convert';
import 'dart:js_interop';
import 'package:clurit/clurit.dart';
import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;
import 'posts.clurit.dart';

class PostsComponentClient extends PostsComponent {
  PostsComponentClient({super.loading, super.errorMessage, super.posts});

  late final CapturedNodes _nodes;

  Future<void> hydrate(web.Element root) async {
    _nodes = captureClNodes(root);
    bindActions(_nodes, {'retry': retry});

    registerUpdater('loading', _applyBinding1);
    registerUpdater('errorMessage', _applyBinding2);
    registerUpdater('posts', _applyBinding4);
    onInit();
  }

  void _applyBinding1() {
    _nodes.anchors[1]!.setNodes(ExpressionEvaluator.isTruthy(loading)
        ? _fragment1Then()
        : _fragment1Else());
  }

  List<web.Node> _fragment1Then() {
    final buf = StringBuffer();
    buf.write(
        '\n        <div class="flex items-center gap-2 text-slate-500">\n            <span class="inline-block w-4 h-4 border-2 border-slate-300 border-t-blue-600 rounded-full animate-spin"></span>\n            Loading posts...\n        </div>\n    ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment1Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }

  void _applyBinding2() {
    _nodes.anchors[2]!.setNodes(
        ExpressionEvaluator.isTruthy(errorMessage != null)
            ? _fragment2Then()
            : _fragment2Else());
  }

  List<web.Node> _fragment2Then() {
    final buf = StringBuffer();
    buf.write(
        '\n        <div class="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4">\n            <p>');
    buf.write('<!--cl:3-->');
    buf.write(escapeHtml(stringify(errorMessage)));
    buf.write('<!--/cl:3-->');
    buf.write(
        '</p>\n            <button cl-click="retry" class="mt-2 px-3 py-1 rounded bg-red-600 text-white">Retry</button>\n        </div>\n    ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment2Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }

  void _applyBinding4() {
    _nodes.anchors[4]!.setNodes(ExpressionEvaluator.isTruthy(posts.isNotEmpty)
        ? _fragment4Then()
        : _fragment4Else());
  }

  List<web.Node> _fragment4Then() {
    final buf = StringBuffer();
    buf.write('\n        <ul class="space-y-3">\n            ');
    buf.write('<!--cl-for:5-->');
    for (final post in (posts)) {
      buf.write(
          '\n                <li class="bg-white rounded-lg shadow p-4">\n                    <h3 class="font-semibold">');
      buf.write('<!--cl:6-->');
      buf.write(escapeHtml(stringify(post['title'])));
      buf.write('<!--/cl:6-->');
      buf.write(
          '</h3>\n                    <p class="text-slate-500 text-sm mt-1">');
      buf.write('<!--cl:7-->');
      buf.write(escapeHtml(stringify(post['body'])));
      buf.write('<!--/cl:7-->');
      buf.write('</p>\n                </li>\n            ');
    }
    buf.write('<!--/cl-for:5-->');
    buf.write('\n        </ul>\n    ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment4Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }

  void retry() {
    onInit();
  }

  void onInit() {
    loading = true;
    errorMessage = null;
    web.window
        .fetch('https://jsonplaceholder.typicode.com/posts'.toJS)
        .toDart
        .then((response) {
      if (!response.ok) {
        throw Exception('HTTP ${response.status}');
      }
      return response.text().toDart;
    }).then((text) {
      final decoded =
          (jsonDecode(text.toDart) as List).cast<Map<String, dynamic>>();
      posts = decoded.take(10).toList();
      loading = false;
    }).catchError((e) {
      errorMessage = 'Failed to load posts: $e';
      loading = false;
    });
  }
}
