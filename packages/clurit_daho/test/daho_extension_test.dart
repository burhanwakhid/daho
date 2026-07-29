import 'package:clurit/clurit.dart';
import 'package:clurit_daho/clurit_daho.dart';
import 'package:daho/daho.dart';
import 'package:test/test.dart';

class _FakeComponent extends CluritComponent {
  @override
  String renderInitial() => '<div>fake</div>';

  @override
  Map<String, dynamic> initialStateJson() => {};
}

void main() {
  group('CluritDahoExtension.configureClurit', () {
    test('bulk-registers a components map in one call', () {
      final app = Daho();
      final fake = _FakeComponent();

      app.configureClurit(
        viewsPath: 'views',
        components: {'index': (data) => fake},
      );

      final factory = CluritDahoExtension.factoryFor('index');
      expect(factory, isNotNull);
      expect(factory!({}), same(fake));
    });

    test('registerComponent still works standalone (not a breaking change)', () {
      final app = Daho();
      final fake = _FakeComponent();

      app.configureClurit(viewsPath: 'views');
      app.registerComponent('manual', (data) => fake);

      expect(CluritDahoExtension.factoryFor('manual')!({}), same(fake));
    });
  });
}
