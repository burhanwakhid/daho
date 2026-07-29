import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// A `<!--cl:N-->`/`<!--/cl:N-->` (or `cl-if:N`/`cl-for:N`) comment pair
/// bracketing a reactive template region, captured once at hydration time.
/// Every later update indexes directly into the already-captured [start]/
/// [end] comment nodes — no DOM querying ever happens again.
class AnchorRange {
  final web.Comment start;
  final web.Comment end;

  AnchorRange(this.start, this.end);

  web.Node get parent => start.parentNode!;

  /// Removes everything currently between the anchors.
  void clear() {
    var node = start.nextSibling;
    while (node != null && node != end) {
      final next = node.nextSibling;
      parent.removeChild(node);
      node = next;
    }
  }

  bool get hasContent => start.nextSibling != end;

  /// Replaces the anchor's content with a single text node — the compiled
  /// update for a `{{ }}` echo binding.
  void setText(String text) {
    clear();
    parent.insertBefore(web.Text(text), end);
  }

  /// Shows or hides the anchor's content, building it fresh via [build]
  /// only when transitioning from hidden to shown — the compiled update
  /// for an `@if` binding.
  void setVisible(bool visible, web.Node Function() build) {
    if (visible && !hasContent) {
      parent.insertBefore(build(), end);
    } else if (!visible && hasContent) {
      clear();
    }
  }

  /// Replaces the anchor's content with freshly built [nodes] — the
  /// (currently clear-and-rebuild, not keyed-diffed) compiled update for
  /// an `@foreach` binding. See the README's roadmap for keyed diffing.
  void setNodes(Iterable<web.Node> nodes) {
    clear();
    for (final node in nodes) {
      parent.insertBefore(node, end);
    }
  }
}

/// The result of a single hydration-time DOM walk: every anchor-comment
/// binding, keyed by its compile-time-assigned id; every `cl-click`
/// element, keyed by its action name; and every `cl-model` element, keyed
/// by its bound field name.
class CapturedNodes {
  final Map<int, AnchorRange> anchors;
  final Map<String, web.Element> actions;
  final Map<String, web.Element> models;

  CapturedNodes(this.anchors, this.actions, this.models);
}

/// Walks [root] exactly once, in document order, collecting every
/// anchor-comment binding and `cl-click` element. This is the only DOM
/// traversal client hydration ever performs — no `querySelectorAll` sweeps
/// happen afterward; generated update closures index directly into the
/// maps returned here.
CapturedNodes captureClNodes(web.Node root) {
  final anchors = <int, AnchorRange>{};
  final actions = <String, web.Element>{};
  final models = <String, web.Element>{};
  final openAnchors = <String, web.Comment>{};
  final anchorPattern = RegExp(r'^(/?)(cl(?:-if|-for)?):(\d+)$');

  void visit(web.Node node) {
    if (node.nodeType == web.Node.COMMENT_NODE) {
      final data = (node as web.Comment).data.trim();
      final match = anchorPattern.firstMatch(data);
      if (match != null) {
        final isEnd = match.group(1) == '/';
        final key = '${match.group(2)}:${match.group(3)}';
        if (isEnd) {
          final start = openAnchors.remove(key);
          if (start != null) {
            anchors[int.parse(match.group(3)!)] = AnchorRange(start, node);
          }
        } else {
          openAnchors[key] = node;
        }
      }
    } else if (node.nodeType == web.Node.ELEMENT_NODE) {
      final el = node as web.Element;
      final action = el.getAttribute('cl-click');
      if (action != null) actions[action] = el;
      final model = el.getAttribute('cl-model');
      if (model != null) models[model] = el;
    }

    final children = node.childNodes;
    for (var i = 0; i < children.length; i++) {
      final child = children.item(i);
      if (child != null) visit(child);
    }
  }

  visit(root);
  return CapturedNodes(anchors, actions, models);
}

/// Wires each `cl-click="name"` element captured in [nodes] to its
/// corresponding [handlers] entry — a one-time listener attachment done
/// once during hydration, not a runtime dispatch-by-string-lookup on every
/// click.
void bindActions(CapturedNodes nodes, Map<String, void Function()> handlers) {
  handlers.forEach((name, handler) {
    nodes.actions[name]?.addEventListener(
      'click',
      ((web.Event _) => handler()).toJS,
    );
  });
}

/// Wires two-way binding for each `cl-model="field"` element captured in
/// [nodes]: an `input` listener calls the matching [setters] entry with
/// the element's current text value — the "write" half of two-way
/// binding. Pair with [setModelValue], registered as a normal field
/// updater, for the "read" half (keeping the element in sync when the
/// field changes from elsewhere, e.g. a reset button).
void bindModels(
    CapturedNodes nodes, Map<String, void Function(String)> setters) {
  setters.forEach((field, setValue) {
    nodes.models[field]?.addEventListener(
      'input',
      ((web.Event e) => setValue(_elementValue(e.target))).toJS,
    );
  });
}

/// Syncs a `cl-model="field"` element's value to [value], only touching
/// the DOM when it actually differs (so typing isn't disrupted by the
/// echo of the very input that triggered it).
void setModelValue(CapturedNodes nodes, String field, String value) {
  final el = nodes.models[field];
  if (el == null) return;
  if (_elementValue(el) != value) _setElementValue(el, value);
}

String _elementValue(web.EventTarget? target) {
  if (target == null) return '';
  if (target.isA<web.HTMLInputElement>()) {
    return (target as web.HTMLInputElement).value;
  }
  if (target.isA<web.HTMLTextAreaElement>()) {
    return (target as web.HTMLTextAreaElement).value;
  }
  if (target.isA<web.HTMLSelectElement>()) {
    return (target as web.HTMLSelectElement).value;
  }
  return '';
}

void _setElementValue(web.Element el, String value) {
  if (el.isA<web.HTMLInputElement>())
    (el as web.HTMLInputElement).value = value;
  if (el.isA<web.HTMLTextAreaElement>())
    (el as web.HTMLTextAreaElement).value = value;
  if (el.isA<web.HTMLSelectElement>())
    (el as web.HTMLSelectElement).value = value;
}

/// Parses an HTML fragment string into real DOM nodes via a `<template>`
/// element, for inserting into an [AnchorRange] — used by generated
/// `@if`/`@foreach` fragment-rebuild methods, which render their content to
/// a string through the exact same code path as SSR.
List<web.Node> parseFragment(String html) {
  final template =
      web.document.createElement('template') as web.HTMLTemplateElement;
  template.innerHTML = html.toJS;
  final nodes = <web.Node>[];
  final children = template.content.childNodes;
  for (var i = 0; i < children.length; i++) {
    final node = children.item(i);
    if (node != null) nodes.add(node);
  }
  return nodes;
}

/// Decodes the `<script id="clurit-state">` tag's JSON payload emitted by
/// [CodeNode]/a generated component's `initialStateJson()`.
Map<String, dynamic> readInitialState([String elementId = 'clurit-state']) {
  final script = web.document.getElementById(elementId);
  final text = script?.textContent?.trim();
  if (text == null || text.isEmpty) return {};
  return (jsonDecode(text) as Map).cast<String, dynamic>();
}
