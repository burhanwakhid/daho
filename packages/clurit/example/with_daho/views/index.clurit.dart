// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';

class IndexComponent extends CluritComponent {
  int _counter;
  int get counter => _counter;
  set counter(int value) {
    if (_counter == value) return;
    _counter = value;
    markDirty('counter');
  }

  List<String> _items;
  List<String> get items => _items;
  set items(List<String> value) {
    if (_items == value) return;
    _items = value;
    markDirty('items');
  }

  String _name;
  String get name => _name;
  set name(String value) {
    if (_name == value) return;
    _name = value;
    markDirty('name');
  }

  dynamic get fullName {return '$firstName $lastName';}

  final String message;

  IndexComponent({int? counter, List<String>? items, String? name, required this.message}) : _counter = counter ?? 0, _items = items ?? [], _name = name ?? '';

final pageTitle = 'Home';

final firstName = 'Clurit';

final lastName = 'Engine';

void increment() {counter = counter + 1;}

void reset() {counter = 0;}

void loadItems() {items = ['Dart WASM', 'Daho Server', 'Clurit Engine'];}

void clearName() {name = '';}

  @override
  String renderInitial() {
    final buf = StringBuffer();
     buf.write('\n\n');
     buf.write('\n\n');
     buf.write('\n');
     buf.write('<!DOCTYPE html>\n<html lang="en">\n<head>\n    <meta charset="UTF-8">\n    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n    <title>');
     buf.write('<!--cl:0-->');
     buf.write(escapeHtml(stringify(pageTitle)));
     buf.write('<!--/cl:0-->');
     buf.write(' — Daho + Clurit</title>\n    <script src="https://cdn.tailwindcss.com"></script>\n</head>\n<body class="min-h-screen bg-slate-50 text-slate-900">\n    <nav class="bg-blue-600 text-white shadow">\n        <div class="max-w-3xl mx-auto px-4 py-3 flex gap-6">\n            <a href="/" class="font-semibold hover:underline">Home</a>\n            <a href="/greeter" class="hover:underline">Greeter</a>\n            <a href="/posts" class="hover:underline">Posts</a>\n        </div>\n    </nav>\n\n    <main id="app" class="max-w-3xl mx-auto px-4 py-8">\n        ');
     buf.write('\n    <h1 class="text-2xl font-bold mb-4">Welcome to Daho + Clurit!</h1>\n    <p class="text-slate-500 mb-4">');
     buf.write('<!--cl:1-->');
     buf.write(escapeHtml(stringify(message)));
     buf.write('<!--/cl:1-->');
     buf.write('</p>\n\n    <div class="bg-white rounded-lg shadow p-6 space-y-2">\n        <p>Full Name: <strong>');
     buf.write('<!--cl:2-->');
     buf.write(escapeHtml(stringify(fullName)));
     buf.write('<!--/cl:2-->');
     buf.write('</strong></p>\n        <p>Counter: <strong>');
     buf.write('<!--cl:3-->');
     buf.write(escapeHtml(stringify(counter)));
     buf.write('<!--/cl:3-->');
     buf.write('</strong></p>\n\n        <div class="flex items-center gap-2">\n            <label class="flex items-center gap-2">\n                Your name:\n                <input cl-model="name" value="');
     buf.write(escapeHtml(stringify(name)));
     buf.write('" placeholder="Type here..."\n                       class="border rounded px-2 py-1">\n            </label>\n            <button cl-click="clearName" class="px-3 py-1 rounded border">Clear</button>\n        </div>\n        <p>Hello, <strong>');
     buf.write('<!--cl:4-->');
     buf.write(escapeHtml(stringify(name)));
     buf.write('<!--/cl:4-->');
     buf.write('</strong>!</p>\n\n        <div class="flex gap-2">\n            <button cl-click="increment" class="px-3 py-1 rounded bg-blue-600 text-white">Increment (+)</button>\n            <button cl-click="reset" class="px-3 py-1 rounded border">Reset</button>\n            <button cl-click="loadItems" class="px-3 py-1 rounded border">Load Items</button>\n        </div>\n\n        ');
     buf.write('<!--cl-if:5-->');
     if (ExpressionEvaluator.isTruthy(counter > 5)) {
       buf.write('\n            <div class="text-red-600 font-semibold">Wow! Counter reached ');
       buf.write('<!--cl:6-->');
       buf.write(escapeHtml(stringify(counter)));
       buf.write('<!--/cl:6-->');
       buf.write('!</div>\n        ');
     }
     buf.write('<!--/cl-if:5-->');
     buf.write('\n    </div>\n\n    <h3 class="text-lg font-semibold mt-6 mb-2">Dynamic Items:</h3>\n    <ul class="list-disc list-inside space-y-1">\n        ');
     buf.write('<!--cl-for:7-->');
     for (final item in (items)) {
       buf.write('\n            <li>');
       buf.write('<!--cl:8-->');
       buf.write(escapeHtml(stringify(item)));
       buf.write('<!--/cl:8-->');
       buf.write('</li>\n        ');
     }
     buf.write('<!--/cl-for:7-->');
     buf.write('\n    </ul>\n');
     buf.write('\n    </main>\n\n    <footer class="max-w-3xl mx-auto px-4 py-6 text-sm text-slate-400">\n        Clurit — compile-time reactive components\n    </footer>\n\n    <script id="clurit-state" type="application/json"></script>\n    <script src="/js/main.dart.js" defer></script>\n    ');
     buf.write('\n</body>\n</html>\n');
    return buf.toString();
  }

  @override
  Map<String, dynamic> initialStateJson() => {
    'counter': counter,
    'items': items,
    'name': name,
    'message': message,
  };
}
