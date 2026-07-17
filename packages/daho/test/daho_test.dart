import 'dart:convert';
import 'dart:io';

import 'package:daho/daho.dart';
import 'package:test/test.dart';

import 'testing.dart';

Future<void> requireKey(
  DahoRequest req,
  DahoResponse res,
  NextFunction next,
) async {
  if (req.header('x-key') != 'secret') {
    res.status(401).json({'error': 'unauthorized'});
    return;
  }
  await next();
}

void notFound(DahoRequest req, DahoResponse res) =>
    res.status(404).json({'custom': true});

void main() {
  group('routing', () {
    test('static + param routes', () async {
      final t = DahoTester((app) {
        app.get('/ping', (req, res) => res.ok('pong'));
        app.get('/users/:id', (req, res) => res.ok({'id': req.params['id']}));
      });
      expect((await t.get('/ping')).text, 'pong');
      final res = await t.get('/users/42');
      expect(res.statusCode, 200);
      expect(res.json['id'], '42');
    });

    test('custom 404 and 405', () async {
      final t = DahoTester(
        (app) => app.get('/only', (req, res) => res.ok('ok')),
        config: const DahoConfig(notFoundHandler: notFound),
      );
      expect((await t.get('/missing')).json['custom'], true);
      final res = await t.post('/only');
      expect(res.statusCode, 405);
      expect(res.headers['Allow'], contains('GET'));
    });
  });

  group('body parsing', () {
    test('json', () async {
      final t = DahoTester(
        (app) => app.post('/echo', (req, res) => res.ok(req.body)),
      );
      final res = await t.post('/echo', json: {'a': 1, 'b': 'x'});
      expect(res.json, {'a': 1, 'b': 'x'});
    });

    test('urlencoded', () async {
      final t = DahoTester(
        (app) => app.post('/echo', (req, res) => res.ok(req.body)),
      );
      final res = await t.post('/echo', form: 'name=budi&age=30');
      expect(res.json, {'name': 'budi', 'age': '30'});
    });
  });

  group('middleware', () {
    test('per-route guard short-circuits', () async {
      final t = DahoTester((app) {
        app.get(
          '/secure',
          (req, res) => res.ok({'ok': true}),
          use: [requireKey],
        );
      });
      expect((await t.get('/secure')).statusCode, 401);
      expect(
        (await t.get('/secure', headers: {'x-key': 'secret'})).statusCode,
        200,
      );
    });

    test('cors preflight handled globally', () async {
      final t = DahoTester((app) {
        app.use(Middlewares.cors());
        app.get('/data', (req, res) => res.ok('x'));
      });
      final res = await t.request('OPTIONS', '/data');
      expect(res.statusCode, 204);
      expect(res.headers['Access-Control-Allow-Origin'], '*');
      expect(res.headers['Access-Control-Allow-Methods'], contains('GET'));
    });

    test('security headers applied', () async {
      final t = DahoTester((app) {
        app.use(Middlewares.secureHeaders());
        app.get('/', (req, res) => res.ok('x'));
      });
      final res = await t.get('/');
      expect(res.headers['X-Content-Type-Options'], 'nosniff');
      expect(res.headers['X-Frame-Options'], 'DENY');
    });

    test('gzip compression', () async {
      final big = 'a' * 2000;
      final t = DahoTester((app) {
        app.use(Middlewares.compress());
        app.get('/big', (req, res) => res.send(big));
      });
      final res = await t.get('/big', headers: {'Accept-Encoding': 'gzip'});
      expect(res.headers['Content-Encoding'], 'gzip');
      expect(utf8.decode(gzip.decode(res.bodyBytes)), big);
    });

    test('error handler hides internals', () async {
      final t = DahoTester(
        (app) => app.get('/boom', (req, res) => throw StateError('secret')),
      );
      final res = await t.get('/boom');
      expect(res.statusCode, 500);
      expect(res.text, isNot(contains('secret')));
    });
  });

  group('cookies', () {
    test('read and set', () async {
      final t = DahoTester((app) {
        app.get('/c', (req, res) {
          res.cookie('sid', 'v1', httpOnly: true);
          return res.ok({'in': req.cookies['given']});
        });
      });
      final res = await t.get('/c', headers: {'Cookie': 'given=hello'});
      expect(res.json['in'], 'hello');
      expect(res.cookies.first, contains('sid=v1'));
      expect(res.cookies.first, contains('HttpOnly'));
    });
  });
}
