// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';

class CounterComponent extends CluritComponent {
  int _count;
  int get count => _count;
  set count(int value) {
    if (_count == value) return;
    _count = value;
    markDirty('count');
  }

  List<String> _logs;
  List<String> get logs => _logs;
  set logs(List<String> value) {
    if (_logs == value) return;
    _logs = value;
    markDirty('logs');
  }

  String _name;
  String get name => _name;
  set name(String value) {
    if (_name == value) return;
    _name = value;
    markDirty('name');
  }

  dynamic get doubled => count * 2;

  CounterComponent({int? count, List<String>? logs, String? name}) : _count = count ?? 0, _logs = logs ?? [], _name = name ?? '';

void increment() {count = count + 1; logs = [...logs, 'Incremented to $count'];}

void reset() {count = 0; logs = [];}

void clearName() {name = '';}

  @override
  String renderInitial() {
    final buf = StringBuffer();
     buf.write('\n\n<div style="padding: 2rem; max-width: 600px; margin: 0 auto; font-family: sans-serif;">\n    <h1 style="font-size: 2rem; margin-bottom: 1rem;">Clurit Interactive Counter</h1>\n\n    <div style="background: #f3f4f6; padding: 1.5rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">\n        <p style="font-size: 1.25rem;">\n            Current Count: <strong style="color: #2563eb;">');
     buf.write('<!--cl:0-->');
     buf.write(escapeHtml(stringify(count)));
     buf.write('<!--/cl:0-->');
     buf.write('</strong>\n            (doubled: <strong>');
     buf.write('<!--cl:1-->');
     buf.write(escapeHtml(stringify(doubled)));
     buf.write('<!--/cl:1-->');
     buf.write('</strong>)\n        </p>\n\n        <div style="margin-top: 1rem; display: flex; gap: 0.5rem;">\n            <button cl-click="increment"\n                    style="background: #2563eb; color: white; border: none; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer;">\n                Increment\n            </button>\n\n            <button cl-click="reset"\n                    style="background: transparent; border: 1px solid #d1d5db; padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer;">\n                Reset\n            </button>\n        </div>\n\n        ');
     buf.write('<!--cl-if:2-->');
     if (ExpressionEvaluator.isTruthy(count > 10)) {
       buf.write('\n            <p style="color: #16a34a; font-weight: 600;">Goal reached!</p>\n        ');
     }
     buf.write('<!--/cl-if:2-->');
     buf.write('\n\n        <div style="margin-top: 1rem;">\n            <label>\n                Your name:\n                <input cl-model="name" value="');
     buf.write(escapeHtml(stringify(name)));
     buf.write('" placeholder="Type here...">\n            </label>\n            <button cl-click="clearName">Clear</button>\n            <p>Hello, <strong>');
     buf.write('<!--cl:3-->');
     buf.write(escapeHtml(stringify(name)));
     buf.write('<!--/cl:3-->');
     buf.write('</strong>!</p>\n        </div>\n    </div>\n\n    ');
     buf.write('<!--cl-if:4-->');
     if (ExpressionEvaluator.isTruthy(logs.isNotEmpty)) {
       buf.write('\n        <div style="margin-top: 2rem;">\n            <h3 style="font-weight: 600; margin-bottom: 0.5rem;">Action Logs:</h3>\n            ');
       buf.write('<!--cl-for:5-->');
       for (final log in (logs)) {
         buf.write('\n                <div style="font-size: 0.875rem; color: #6b7280; border-left: 2px solid #e5e7eb; padding-left: 0.5rem; margin-bottom: 0.25rem;">\n                    ');
         buf.write('<!--cl:6-->');
         buf.write(escapeHtml(stringify(log)));
         buf.write('<!--/cl:6-->');
         buf.write('\n                </div>\n            ');
       }
       buf.write('<!--/cl-for:5-->');
       buf.write('\n        </div>\n    ');
     }
     buf.write('<!--/cl-if:4-->');
     buf.write('\n</div>\n');
    return buf.toString();
  }

  @override
  Map<String, dynamic> initialStateJson() => {
    'count': count,
    'logs': logs,
    'name': name,
  };
}
