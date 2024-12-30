import 'dart:io';

import 'package:http/http.dart' as http;

class HttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final Duration timeout;
  final String userAgent;

  HttpClient({required this.timeout}) : userAgent = _buildUserAgent();

  static String _buildUserAgent() {
    final os = Platform.operatingSystem; // e.g., linux, macos, windows
    final osVersion = Platform.operatingSystemVersion; // e.g., Linux 5.15.0
    final architecture =
        Platform.version.contains('x64') ? 'x64' : 'x86'; // Simplistic architecture detection
    final dartVersion = Platform.version.split(' ').first;

    // Build User-Agent string
    return [
      'Mozilla/5.0',
      '($os $osVersion; $architecture; en-us)',
      'Dart/$dartVersion',
      '(KHTML, like Gecko)',
      'speedtest-dart/1.0',
    ].join(' ');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = userAgent;
    request.headers['Cache-Control'] = 'no-cache';
    request.headers['Accept-Encoding'] = 'gzip';

    // Add a timeout to the request
    return _inner.send(request).timeout(timeout);
  }
}
