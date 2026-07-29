import 'package:clurit/clurit_client.dart';
import 'package:web/web.dart' as web;
import '../views/pages/counter.clurit.client.dart';

void main() {
  final root = web.document.querySelector('#app');
  if (root == null) return;

  final state = readInitialState();
  final component = CounterComponentClient(
    count: (state['count'] as int?) ?? 0,
    logs: (state['logs'] as List?)?.cast<String>() ?? [],
  );
  component.hydrate(root);
}
