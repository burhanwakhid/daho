// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';
import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;
import 'greeter.clurit.dart';

class GreeterComponentClient extends GreeterComponent {
  GreeterComponentClient({super.greetIndex});

  late final CapturedNodes _nodes;

  Future<void> hydrate(web.Element root) async {
    _nodes = captureClNodes(root);
    bindActions(_nodes, {'nextName': nextName});

    registerUpdater('greetIndex', _applyBinding1);
  }

  void _applyBinding1() {
    _nodes.anchors[1]!.setText(escapeHtml(stringify(currentName)));
  }
}
