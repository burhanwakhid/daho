// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';

class PostsComponent extends CluritComponent {
  bool _loading;
  bool get loading => _loading;
  set loading(bool value) {
    if (_loading == value) return;
    _loading = value;
    markDirty('loading');
  }

  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  set errorMessage(String? value) {
    if (_errorMessage == value) return;
    _errorMessage = value;
    markDirty('errorMessage');
  }

  List<Map<String, dynamic>> _posts;
  List<Map<String, dynamic>> get posts => _posts;
  set posts(List<Map<String, dynamic>> value) {
    if (_posts == value) return;
    _posts = value;
    markDirty('posts');
  }

  PostsComponent(
      {bool? loading, String? errorMessage, List<Map<String, dynamic>>? posts})
      : _loading = loading ?? true,
        _errorMessage = errorMessage ?? null,
        _posts = posts ?? [];

  final pageTitle = 'Posts';

  @override
  String renderInitial() {
    final buf = StringBuffer();
    buf.write('\n\n');
    buf.write('\n\n');
    buf.write('\n');
    buf.write(
        '<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>');
    buf.write('<!--cl:0-->');
    buf.write(escapeHtml(stringify(pageTitle)));
    buf.write('<!--/cl:0-->');
    buf.write(
        ' — Daho + Clurit</title>\n    <script src="https://cdn.tailwindcss.com"></script>\n</head>\n<body class="min-h-screen bg-slate-50 text-slate-900">\n    <nav class="bg-blue-600 text-white shadow">\n        <div class="max-w-3xl mx-auto px-4 py-3 flex gap-6">\n            <a href="/" class="font-semibold hover:underline">Home</a>\n            <a href="/greeter" class="hover:underline">Greeter</a>\n            <a href="/posts" class="hover:underline">Posts</a>\n        </div>\n    </nav>\n\n    <main id="app" class="max-w-3xl mx-auto px-4 py-8">\n        ');
    buf.write(
        '\n    <h1 class="text-2xl font-bold mb-4">Posts</h1>\n    <p class="text-slate-500 mb-4">Fetched client-side from jsonplaceholder.typicode.com</p>\n\n    ');
    buf.write('<!--cl-if:1-->');
    if (ExpressionEvaluator.isTruthy(loading)) {
      buf.write(
          '\n        <div class="flex items-center gap-2 text-slate-500">\n            <span class="inline-block w-4 h-4 border-2 border-slate-300 border-t-blue-600 rounded-full animate-spin"></span>\n            Loading posts...\n        </div>\n    ');
    }
    buf.write('<!--/cl-if:1-->');
    buf.write('\n\n    ');
    buf.write('<!--cl-if:2-->');
    if (ExpressionEvaluator.isTruthy(errorMessage != null)) {
      buf.write(
          '\n        <div class="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4">\n            <p>');
      buf.write('<!--cl:3-->');
      buf.write(escapeHtml(stringify(errorMessage)));
      buf.write('<!--/cl:3-->');
      buf.write(
          '</p>\n            <button cl-click="retry" class="mt-2 px-3 py-1 rounded bg-red-600 text-white">Retry</button>\n        </div>\n    ');
    }
    buf.write('<!--/cl-if:2-->');
    buf.write('\n\n    ');
    buf.write('<!--cl-if:4-->');
    if (ExpressionEvaluator.isTruthy(posts.isNotEmpty)) {
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
    }
    buf.write('<!--/cl-if:4-->');
    buf.write('\n');
    buf.write(
        '\n    </main>\n\n    <footer class="max-w-3xl mx-auto px-4 py-6 text-sm text-slate-400">\n        Clurit — compile-time reactive components\n    </footer>\n\n    <script id="clurit-state" type="application/json"></script>\n    <script src="/js/main.dart.js" defer></script>\n    ');
    buf.write('\n</body>\n</html>\n');
    return buf.toString();
  }

  @override
  Map<String, dynamic> initialStateJson() => {
        'loading': loading,
        'errorMessage': errorMessage,
        'posts': posts,
      };
}
