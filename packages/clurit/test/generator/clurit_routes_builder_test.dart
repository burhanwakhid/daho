import 'package:build/build.dart';
import 'package:clurit/src/generator/clurit_routes_builder.dart';
import 'package:clurit/src/generator/code_analyzer.dart';
import 'package:test/test.dart';

ComponentAnalyzerResult _fixtureComponent({
  required String className,
  List<StateField> stateFields = const [],
  List<PropField> propFields = const [],
  String? clientImportPath,
  String? serverImportPath,
}) {
  return ComponentAnalyzerResult(
    model: ComponentModel(
      stateFields: stateFields,
      derivedFields: const [],
      propFields: propFields,
      effects: const [],
      plainMemberSources: const [],
      eventHandlerNames: const [],
    ),
    className: className,
    clientImportPath: clientImportPath ??
        '../views/${className.toLowerCase()}.clurit.client.dart',
    serverImportPath:
        serverImportPath ?? 'views/${className.toLowerCase()}.clurit.dart',
  );
}

void main() {
  final builder = CluritRoutesBuilder();

  group('CluritRoutesBuilder.routeFor', () {
    test('maps index.clurit to the root route', () {
      expect(builder.routeFor(AssetId('app', 'views/index.clurit')), '/');
    });

    test('maps home.clurit to the root route too', () {
      expect(builder.routeFor(AssetId('app', 'views/home.clurit')), '/');
    });

    test('maps any other filename to /<filename>', () {
      expect(
          builder.routeFor(AssetId('app', 'views/greeter.clurit')), '/greeter');
      expect(
        builder.routeFor(AssetId('app', 'views/pages/user_profile.clurit')),
        '/user_profile',
      );
    });

    test('declares web/main.g.dart and clurit_components.g.dart as outputs',
        () {
      expect(
        builder.buildExtensions,
        {
          'clurit_routes.yaml': ['web/main.g.dart', 'clurit_components.g.dart'],
        },
      );
    });
  });

  group('CluritRoutesBuilder.emitComponentRegistry', () {
    test('generates a factory map keyed by registry name', () {
      final pages = [
        PageRoute(
          '/',
          _fixtureComponent(
            className: 'IndexComponent',
            stateFields: [
              StateField(name: 'count', type: 'int', initializerSource: '0')
            ],
            propFields: [PropField(name: 'title', type: 'String')],
          ),
        ),
        PageRoute('/greeter', _fixtureComponent(className: 'GreeterComponent')),
      ];

      final output = builder.emitComponentRegistry(pages);

      expect(
        output,
        contains(
          'final Map<String, CluritComponent Function(Map<String, dynamic>)> cluritComponents',
        ),
      );
      expect(
        output,
        contains(
          "'index': (data) => IndexComponent(count: data['count'] as int?, "
          "title: data['title'] as String),",
        ),
      );
      expect(output, contains("'greeter': (data) => GreeterComponent(),"));
    });

    test(
        'casts a nullable-optional \$state List<T> but a required non-null \$props List<T>',
        () {
      final pages = [
        PageRoute(
          '/',
          _fixtureComponent(
            className: 'X',
            stateFields: [
              StateField(
                  name: 'logs', type: 'List<String>', initializerSource: '[]')
            ],
            propFields: [PropField(name: 'tags', type: 'List<String>')],
          ),
        ),
      ];

      final output = builder.emitComponentRegistry(pages);

      expect(output, contains("logs: (data['logs'] as List?)?.cast<String>()"));
      expect(output, contains("tags: (data['tags'] as List).cast<String>()"));
    });
  });

  group('CluritRoutesBuilder.emitClientBootstrap', () {
    test('emits deferred imports, a path switch, and CluritRouter wiring', () {
      final pages = [
        PageRoute(
          '/',
          _fixtureComponent(
            className: 'IndexComponent',
            stateFields: [
              StateField(name: 'count', type: 'int', initializerSource: '0')
            ],
          ),
        ),
        PageRoute('/greeter', _fixtureComponent(className: 'GreeterComponent')),
      ];

      final output = builder.emitClientBootstrap(pages);

      expect(
          output,
          contains(
              "import '../views/indexcomponent.clurit.client.dart' deferred as _page0;"));
      expect(output, contains("case '/greeter':"));
      expect(output, contains('await _page1.loadLibrary();'));
      expect(
        output,
        contains(
            "_page0.IndexComponentClient(count: state['count'] as int?).hydrate(root);"),
      );
      expect(output, contains('CluritRouter('));
      expect(output, contains("contentSelector: '#app',"));
    });
  });
}
