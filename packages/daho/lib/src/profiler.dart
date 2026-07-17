import 'dart:async';
import 'dart:io';

/// Lightweight, per-Isolate request profiler for measuring the framework's
/// server-side cost (independent of the network / load generator).
///
/// Enabled by setting the `DAHO_PROFILE` environment variable to `1`. When
/// disabled, [enabled] is a compile-visible const-like bool and the hot path
/// costs a single field read, so it is safe to leave the calls in place.
///
/// Each worker prints a line every [_interval]:
/// ```
/// [daho-prof w0] 9820 req/s | p50=82us p99=910us max=5.1ms | rss=212MB
/// ```
/// - `req/s`   — requests completed in the last interval (this worker only).
/// - `p50/p99` — in-Dart processing time (dispatch + response marshalling),
///               i.e. excludes kernel/network time that `wrk` also measures.
/// - `rss`     — resident memory of the whole process (shared across workers).
///
/// Timing uses integer microsecond timestamps (no per-request allocation) so
/// the profiler itself does not perturb the GC measurement.
class Profiler {
  static final bool enabled = Platform.environment['DAHO_PROFILE'] == '1';

  static final Map<int, Profiler> _byWorker = {};

  /// Returns the profiler for [workerId], creating it on first use.
  static Profiler forWorker(int workerId) =>
      _byWorker[workerId] ??= Profiler._(workerId);

  final int workerId;
  static const Duration _interval = Duration(seconds: 2);

  // Histogram upper bounds in microseconds.
  static const List<int> _bounds = [
    25,
    50,
    100,
    200,
    500,
    1000,
    2000,
    5000,
    10000,
    50000,
  ];
  final List<int> _buckets = List.filled(_bounds.length + 1, 0);

  int _count = 0;
  int _maxMicros = 0;
  int _totalAllTime = 0;

  Profiler._(this.workerId) {
    Timer.periodic(_interval, (_) => _report());
  }

  /// Records one completed request that took [micros] microseconds in Dart.
  void record(int micros) {
    _count++;
    _totalAllTime++;
    if (micros > _maxMicros) _maxMicros = micros;
    var i = 0;
    while (i < _bounds.length && micros > _bounds[i]) {
      i++;
    }
    _buckets[i]++;
  }

  void _report() {
    if (_count == 0) return;

    final rps = (_count / _interval.inSeconds).round();
    final p50 = _percentile(0.50);
    final p99 = _percentile(0.99);
    final rssMb = (ProcessInfo.currentRss / (1024 * 1024)).round();

    stdout.writeln(
      '[daho-prof w$workerId] $rps req/s | '
      'p50=${_fmt(p50)} p99=${_fmt(p99)} max=${_fmt(_maxMicros)} | '
      'rss=${rssMb}MB | total=$_totalAllTime',
    );

    // Reset per-interval counters (keep _totalAllTime cumulative).
    _count = 0;
    _maxMicros = 0;
    for (var i = 0; i < _buckets.length; i++) {
      _buckets[i] = 0;
    }
  }

  /// Approximate percentile (upper bound of the containing bucket) in micros.
  int _percentile(double q) {
    final target = (q * _count).ceil();
    var cumulative = 0;
    for (var i = 0; i < _buckets.length; i++) {
      cumulative += _buckets[i];
      if (cumulative >= target) {
        return i < _bounds.length ? _bounds[i] : _bounds.last * 2;
      }
    }
    return _maxMicros;
  }

  String _fmt(int micros) => micros >= 1000
      ? '${(micros / 1000).toStringAsFixed(1)}ms'
      : '${micros}us';
}
