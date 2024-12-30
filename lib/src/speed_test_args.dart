enum Unit { bit, byte }

final class SpeedTestArgs {
  /// Perform download test (default: true)
  final bool download;

  /// Perform upload test (default: true)
  final bool upload;

  /// Use a single connection instead of multiple (default: false)
  final bool single;

  /// Display values in bytes instead of bits
  final (Unit, int) units;

  /// Generate and provide a URL to the speedtest.net share results image (default: false)
  final bool share;

  /// Suppress verbose output, only show basic information (default: false)
  final bool simple;

  /// Suppress verbose output, only show basic information in CSV format (default: false)
  final bool csv;

  /// Single character delimiter to use in CSV output (default: ',')
  final String csvDelimiter;

  /// Print CSV headers (default: false)
  final bool csvHeader;

  /// Suppress verbose output, only show basic information in JSON format (default: false)
  final bool json;

  /// Display a list of speedtest.net servers sorted by distance (default: false)
  final bool list;

  /// Specify server IDs to test against (default: empty list)
  final List<int> server;

  /// Exclude server IDs from selection (default: empty list)
  final List<int> exclude;

  /// URL of the Speedtest Mini server (default: null)
  final String? mini;

  /// Source IP address to bind to (default: null)
  final String? source;

  /// HTTP timeout in seconds (default: 10)
  final double timeout;

  /// Use HTTPS instead of HTTP for speedtest.net servers (default: false)
  final bool secure;

  /// Pre-allocate upload data to improve performance (default: true)
  final bool preAllocate;

  /// Show the version number and exit (default: false)
  final bool version;

  /// Enable debug mode (default: false)
  final bool debug;

  /// Constructor with named parameters and default values
  const SpeedTestArgs({
    this.download = true,
    this.upload = true,
    this.single = false,
    this.units = const (Unit.bit, 1),
    this.share = false,
    this.simple = false,
    this.csv = false,
    this.csvDelimiter = ',',
    this.csvHeader = false,
    this.json = false,
    this.list = false,
    this.server = const [],
    this.exclude = const [],
    this.mini,
    this.source,
    this.timeout = 10.0,
    this.secure = false,
    this.preAllocate = true,
    this.version = false,
    this.debug = false,
  });
}
