// GENERATED CODE - DO NOT MODIFY BY HAND
// Regenerate with: dart run build_runner build
// ignore_for_file: type=lint

import 'package:clurit/clurit.dart';
import 'views/index.clurit.dart';
import 'views/greeter.clurit.dart';
import 'views/posts.clurit.dart';

final Map<String, CluritComponent Function(Map<String, dynamic>)> cluritComponents = {
  'index': (data) => IndexComponent(counter: data['counter'] as int?, items: (data['items'] as List?)?.cast<String>(), name: data['name'] as String?, message: data['message'] as String),
  'greeter': (data) => GreeterComponent(greetIndex: data['greetIndex'] as int?),
  'posts': (data) => PostsComponent(loading: data['loading'] as bool?, errorMessage: data['errorMessage'], posts: (data['posts'] as List?)?.cast<Map<String, dynamic>>()),
};
