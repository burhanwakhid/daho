// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';
import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;
import 'index.clurit.dart';

class IndexComponentClient extends IndexComponent {
  IndexComponentClient(
      {super.counter, super.items, super.name, required super.message});

  late final CapturedNodes _nodes;

  Future<void> hydrate(web.Element root) async {
    _nodes = captureClNodes(root);
    bindActions(_nodes, {
      'increment': increment,
      'reset': reset,
      'loadItems': loadItems,
      'clearName': clearName
    });

    registerUpdater('counter', _applyBinding2);
    registerUpdater('items', _applyBinding2);
    registerUpdater('name', _applyBinding2);
    registerUpdater('counter', _applyBinding3);
    registerUpdater('name', _applyBinding4);
    registerUpdater('counter', _applyBinding5);
    registerUpdater('items', _applyBinding7);
    bindModels(_nodes, {'name': (v) => name = v});
    registerUpdater(
        'name', () => setModelValue(_nodes, 'name', name.toString()));

    registerUpdater('counter', _effect0);

    _effect0();
    onInit();
  }

  void _applyBinding2() {
    _nodes.anchors[2]!.setText(escapeHtml(stringify(fullName)));
  }

  void _applyBinding3() {
    _nodes.anchors[3]!.setText(escapeHtml(stringify(counter)));
  }

  void _applyBinding4() {
    _nodes.anchors[4]!.setText(escapeHtml(stringify(name)));
  }

  void _applyBinding5() {
    _nodes.anchors[5]!.setNodes(ExpressionEvaluator.isTruthy(counter > 5)
        ? _fragment5Then()
        : _fragment5Else());
  }

  List<web.Node> _fragment5Then() {
    final buf = StringBuffer();
    buf.write(
        '\n            <div class="text-red-600 font-semibold">Wow! Counter reached ');
    buf.write('<!--cl:6-->');
    buf.write(escapeHtml(stringify(counter)));
    buf.write('<!--/cl:6-->');
    buf.write('!</div>\n        ');
    return parseFragment(buf.toString());
  }

  List<web.Node> _fragment5Else() {
    final buf = StringBuffer();
    return parseFragment(buf.toString());
  }

  void _applyBinding7() {
    final _items7 = (items);
    final _built7 = <web.Node>[];
    for (final item in _items7) {
      _built7.addAll(_fragmentItem7(item));
    }
    _nodes.anchors[7]!.setNodes(_built7);
  }

  List<web.Node> _fragmentItem7(dynamic item) {
    final buf = StringBuffer();
    buf.write('\n            <li>');
    buf.write('<!--cl:8-->');
    buf.write(escapeHtml(stringify(item)));
    buf.write('<!--/cl:8-->');
    buf.write('</li>\n        ');
    return parseFragment(buf.toString());
  }

  void _effect0() {
    print('Clurit: counter is now $counter');
  }

  void onInit() {}
}
