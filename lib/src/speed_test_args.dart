enum Unit { bit, byte }

final class SpeedTestArgs {
  /// Perform download test (default: true)
  final bool download;

  /// Perform upload test (default: true)
  final bool upload;

  /// Perform ping test (default: true)
  final bool ping;

  /// Specify server IDs to test against (default: empty list)
  final List<int> server;

  /// Exclude server IDs from selection (default: empty list)
  final List<int> exclude;

  /// HTTP timeout (default: 3 seconds)
  final Duration httpTimeout;

  /// Maximum time to run the test (default: 10 seconds)
  final Duration duration;

  /// Progress callback interval
  final Duration progressInterval;

  /// Number of pings to perform for ping test (default: 5)
  final int numberOfPings;

  /// Constructor with named parameters and default values
  const SpeedTestArgs({
    this.download = true,
    this.upload = true,
    this.ping = true,
    this.server = const [],
    this.exclude = const [],
    this.httpTimeout = const Duration(seconds: 3),
    this.duration = const Duration(seconds: 10),
    this.progressInterval = const Duration(milliseconds: 150),
    this.numberOfPings = 5,
  });
}
