// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';

class GreeterComponent extends CluritComponent {
  int _greetIndex;
  int get greetIndex => _greetIndex;
  set greetIndex(int value) {
    if (_greetIndex == value) return;
    _greetIndex = value;
    markDirty('greetIndex');
  }

  dynamic get currentName {
    return names[greetIndex % names.length];
  }

  GreeterComponent({int? greetIndex}) : _greetIndex = greetIndex ?? 0;

  final pageTitle = 'Greeter';

  final names = ['Alice', 'Bob', 'Charlie'];

  void nextName() {
    greetIndex = greetIndex + 1;
  }

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
        '\n    <div class="bg-white rounded-lg shadow p-6">\n        <h1 class="text-2xl font-bold mb-4">Hello, ');
    buf.write('<!--cl:1-->');
    buf.write(escapeHtml(stringify(currentName)));
    buf.write('<!--/cl:1-->');
    buf.write(
        '!</h1>\n        <button cl-click="nextName" class="px-3 py-1 rounded bg-blue-600 text-white">Next Person</button>\n    </div>\n');
    buf.write(
        '\n    </main>\n\n    <footer class="max-w-3xl mx-auto px-4 py-6 text-sm text-slate-400">\n        Clurit — compile-time reactive components\n    </footer>\n\n    <script id="clurit-state" type="application/json"></script>\n    <script src="/js/main.dart.js" defer></script>\n    ');
    buf.write('\n</body>\n</html>\n');
    return buf.toString();
  }

  @override
  Map<String, dynamic> initialStateJson() => {
        'greetIndex': greetIndex,
      };
}
