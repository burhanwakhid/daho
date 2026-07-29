/// Client-side runtime for Clurit's compiled reactive components.
///
/// This library is intentionally minimal: DOM capture, anchor insert/
/// remove, and event delegation helpers only — no expression evaluation
/// and no runtime DOM scanning. Every generated `*.clurit.client.dart`
/// component resolves its own bindings once at [captureClNodes] time and
/// indexes directly into the result afterward.
library;

export 'src/client/runtime.dart'
    show
        AnchorRange,
        CapturedNodes,
        captureClNodes,
        bindActions,
        bindModels,
        setModelValue,
        parseFragment,
        readInitialState;
export 'src/client/router.dart' show CluritRouter;
