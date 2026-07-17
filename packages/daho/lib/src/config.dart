import 'dart:async';
import 'dart:io';

import 'request.dart';
import 'response.dart';

/// Maximum number of worker Isolates the framework will spawn.
///
/// Must stay in sync with `MAX_WORKERS` in the C wrapper, which sizes its
/// per-worker arrays to this value.
const int maxWorkers = 64;

/// Handles an error thrown by a route handler or middleware.
///
/// Populate [res] with the response to send. Must be a top-level or static
/// function (never a closure): the config is sent to worker Isolates, and Dart
/// cannot transfer closures across Isolate boundaries.
///
/// Do NOT leak internal details (stack traces, messages) to clients in
/// production — log them server-side instead.
typedef ErrorHandler =
    FutureOr<void> Function(
      DahoRequest req,
      DahoResponse res,
      Object error,
      StackTrace stackTrace,
    );

/// The default [ErrorHandler]: logs the error to stderr and returns a generic
/// `500` that reveals nothing about the failure to the client.
void defaultErrorHandler(
  DahoRequest req,
  DahoResponse res,
  Object error,
  StackTrace stackTrace,
) {
  stderr.writeln('[daho] Unhandled error on ${req.method} ${req.path}: $error');
  stderr.writeln(stackTrace);
  res.status(500).json({'error': 'Internal Server Error'});
}

/// Handles a request that matched no route. Populate [res] with the response.
///
/// Must be a top-level or static function (see [ErrorHandler] for why).
typedef NotFoundHandler =
    FutureOr<void> Function(DahoRequest req, DahoResponse res);

/// The default [NotFoundHandler]: a plain `404`.
void defaultNotFoundHandler(DahoRequest req, DahoResponse res) {
  res.status(404).json({'error': 'Not Found'});
}

/// Global application configuration, analogous to Fiber's `fiber.Config`.
///
/// Immutable so it can be sent across Isolates. Any function-typed field (e.g.
/// [errorHandler]) must therefore be a top-level or static function.
class DahoConfig {
  /// Maximum request body size in bytes.
  ///
  /// Equivalent to Fiber's `BodyLimit` (`fasthttp.MaxRequestBodySize`).
  /// Forwarded to H2O's `max_request_entity_size`, so an oversized request is
  /// rejected with `413 Payload Too Large` *before* its body is read.
  /// Defaults to 4 MB, matching Fiber.
  final int bodyLimit;

  /// Number of worker Isolates (one native H2O server each, sharing the socket
  /// via `SO_REUSEPORT`). `null` uses `Platform.numberOfProcessors`. The value
  /// is clamped to `[1, maxWorkers]`.
  ///
  /// Set this explicitly in containers with a CPU quota, where
  /// `numberOfProcessors` reports host cores rather than the cgroup limit.
  final int? concurrency;

  /// Per-request timeout (HTTP/1 `req_timeout`). [Duration.zero] keeps H2O's
  /// default.
  final Duration requestTimeout;

  /// Keep-alive idle timeout (HTTP/2 `idle_timeout`). [Duration.zero] keeps
  /// H2O's default.
  final Duration idleTimeout;

  /// How long [Daho.listen] waits for in-flight requests to finish after a
  /// shutdown signal before exiting.
  final Duration shutdownGracePeriod;

  /// Invoked when a handler or middleware throws. See [ErrorHandler].
  final ErrorHandler errorHandler;

  /// Invoked when a request matches no route. See [NotFoundHandler].
  final NotFoundHandler notFoundHandler;

  /// When true, `req.ip` is taken from the `X-Forwarded-For` (leftmost) or
  /// `X-Real-IP` header instead of the socket peer address.
  ///
  /// Enable this ONLY when running behind a trusted reverse proxy / load
  /// balancer that sets these headers, otherwise clients can spoof their IP.
  final bool trustProxy;

  /// Suppresses the startup and shutdown log lines when true.
  final bool disableStartupMessage;

  const DahoConfig({
    this.bodyLimit = 4 * 1024 * 1024,
    this.concurrency,
    this.requestTimeout = Duration.zero,
    this.idleTimeout = Duration.zero,
    this.shutdownGracePeriod = const Duration(seconds: 5),
    this.errorHandler = defaultErrorHandler,
    this.notFoundHandler = defaultNotFoundHandler,
    this.trustProxy = false,
    this.disableStartupMessage = false,
  });
}
