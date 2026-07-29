// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';
import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;
import 'counter.clurit.dart';

class CounterComponentClient extends CounterComponent {
  CounterComponentClient({super.count, super.logs, super.name});

  late final CapturedNodes _nodes;

  Future<void> hydrate(web.Element root) async {
    _nodes = captureClNodes(root);
    bindActions(_nodes,
        {'increment': increment, 'reset': reset, 'clearName': clearName});

    registerUpdater('count', _applyBinding0);
    registerUpdater('count', _applyBinding1);
    registerUpdater('logs', _applyBinding1);
    registerUpdater('name', _applyBinding1);
    registerUpdater('count', _applyBinding2);
    registerUpdater('name', _applyBinding3);
    registerUpdater('logs', _applyBinding4);
    bindModels(_nodes, {'name': (v) => name = v});
    registerUpdater(
        'name', () => setModelValue(_nodes, 'name', name.toString()));
  }

  void _applyBinding0() {
    _nodes.anchors[0]!.setText(escapeHtml(stringify(count)));
  }

  void _applyBinding1() {
    _nodes.anchors[1]!.setText(escapeHtml(stringify(doubled)));
  }

  void _applyBinding2() {
    _nodes.anchors[2]!.setNodes(ExpressionEvaluator.isTruthy(count > 10)
        ? _fragment2Then()
        : _fragment2Else());
  }

  List<web.Node> _fragment2Then() {
    final buf = StringBuffer();
    buf.write(
        '\n            <p style="color: #16a34a; font-weight: 600;">Goal reached!</p>\n        ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment2Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }

  void _applyBinding3() {
    _nodes.anchors[3]!.setText(escapeHtml(stringify(name)));
  }

  void _applyBinding4() {
    _nodes.anchors[4]!.setNodes(ExpressionEvaluator.isTruthy(logs.isNotEmpty)
        ? _fragment4Then()
        : _fragment4Else());
  }

  List<web.Node> _fragment4Then() {
    final buf = StringBuffer();
    buf.write(
        '\n        <div style="margin-top: 2rem;">\n            <h3 style="font-weight: 600; margin-bottom: 0.5rem;">Action Logs:</h3>\n            ');
    buf.write('<!--cl-for:5-->');
    for (final log in (logs)) {
      buf.write(
          '\n                <div style="font-size: 0.875rem; color: #6b7280; border-left: 2px solid #e5e7eb; padding-left: 0.5rem; margin-bottom: 0.25rem;">\n                    ');
      buf.write('<!--cl:6-->');
      buf.write(escapeHtml(stringify(log)));
      buf.write('<!--/cl:6-->');
      buf.write('\n                </div>\n            ');
    }
    buf.write('<!--/cl-for:5-->');
    buf.write('\n        </div>\n    ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment4Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }
}
