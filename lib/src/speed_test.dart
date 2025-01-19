import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_ping/dart_ping.dart';
import 'package:dart_ping_ios/dart_ping_ios.dart';
import 'package:dio/dio.dart';
import 'package:flutter_network_speed_test/flutter_network_speed_test.dart';
import 'package:pool/pool.dart';
import 'package:xml/xml.dart';

final class SpeedTest {
  SpeedTest(this.args);

  final SpeedTestArgs args;

  _SpeedTestConfig? _config;
  final Map<double, List<SpeedTestServer>> _servers = {};
  SpeedTestServer? _bestServer;

  Future<void> init() async {
    try {
      await _loadConfig();
      await _getServers();
      await _getBestServer();

      if (!_isIosInited && Platform.isIOS) {
        DartPingIOS.register();
        _isIosInited = true;
      }
    } catch (e) {
      // print(e);
    }
  }

  Future<double> testDownloadSpeed(
      {void Function(double mbps, double progress, double time)? onProgress,
      Duration? duration}) async {
    if (_bestServer == null) {
      throw Exception('Not initialized');
    }

    final httpClient = _getHttpClient(timeout: false);
    final chunksStreamController = StreamController<int>();

    Timer? timeoutTimer;
    Timer? progressTimer;
    Pool? pool;
    final cancelToken = CancelToken();

    try {
      final List<String> urls = [];

      final downloadSizes = _config!.sizes.download;
      final downloadCounts = _config!.counts.download;
      final maxThreads = _config!.threads.download;
      final testDuration = duration ?? args.duration;

      for (final size in downloadSizes) {
        for (int i = 0; i < downloadCounts; i++) {
          urls.add('${_bestServer!.url}/random${size}x$size.jpg');
        }
      }

      final requestsUris = Iterable.generate(
          urls.length, (index) => _buildRequest(uri: urls[index], bump: '$index'));

      final tasks = requestsUris.map((uri) {
        return () async {
          try {
            final streamedResponse = await httpClient.getUri(Uri.parse(uri),
                options: Options(responseType: ResponseType.stream), cancelToken: cancelToken);

            await for (var chunk in streamedResponse.data.stream) {
              if (chunksStreamController.isClosed) {
                break;
              }

              chunksStreamController.add(chunk.length);
            }
          } catch (e) {
            // ignore
          }
        };
      });

      pool = Pool(maxThreads);

      final startTime = DateTime.now().millisecondsSinceEpoch;
      var lastChunkTime = startTime;
      var totalBytes = 0;
      chunksStreamController.stream.listen((chunkLength) {
        totalBytes += chunkLength;
        lastChunkTime = DateTime.now().millisecondsSinceEpoch;
      });

      timeoutTimer = Timer(testDuration, () {
        chunksStreamController.close();
        cancelToken.cancel();
      });

      if (onProgress != null) {
        progressTimer = Timer.periodic(args.progressInterval, (timer) {
          final elapsedTime = (lastChunkTime - startTime) / 1000.0;
          final speedMbps = _getMbps(totalBytes, startTime, lastChunkTime);

          onProgress(speedMbps, elapsedTime / testDuration.inSeconds, elapsedTime);

          if (chunksStreamController.isClosed) {
            timer.cancel();
          }
        });
      }

      await Future.wait(tasks.map((task) => pool!.withResource(task)));
      return _getMbps(totalBytes, startTime, lastChunkTime);
    } finally {
      timeoutTimer?.cancel();
      progressTimer?.cancel();
      await pool?.close();

      if (!chunksStreamController.isClosed) {
        chunksStreamController.close();
        cancelToken.cancel();
      }

      httpClient.close(force: true);
    }
  }

  Future<double> testUploadSpeed(
      {void Function(double mbps, double progress, double time)? onProgress,
      Duration? duration}) async {
    if (_bestServer == null) {
      throw Exception('Not initialized');
    }

    final httpClient = _getHttpClient(timeout: false);
    final chunksStreamController = StreamController<int>();

    Timer? timeoutTimer;
    Timer? progressTimer;
    Pool? pool;
    final cancelToken = CancelToken();

    try {
      final uploadSizes = _config!.sizes.upload;
      final uploadCounts = _config!.counts.upload;
      final maxThreads = _config!.threads.download;
      final testDuration = duration ?? args.duration;

      final sizes = <int>[];
      for (final size in uploadSizes) {
        for (int i = 0; i < uploadCounts; i++) {
          sizes.add(size);
        }
      }

      final contentLength = sizes[0];
      final randomData = Uint8List(contentLength);

      final tasks = sizes.map((uri) {
        return () async {
          try {
            var prevCount = 0;
            await httpClient.postUri(Uri.parse(_bestServer!.url),
                options: Options(headers: {
                  'Content-Length': '$contentLength',
                  'Content-Type': 'application/octet-stream'
                }),
                data: randomData,
                cancelToken: cancelToken, onSendProgress: (count, total) {
              if (!chunksStreamController.isClosed) {
                chunksStreamController.add(count - prevCount);
                prevCount = count;
              }
            });

            if (!chunksStreamController.isClosed) {
              chunksStreamController.add(contentLength - prevCount);
            }
          } catch (e) {
            // ignore
          }
        };
      });

      pool = Pool(maxThreads);

      final startTime = DateTime.now().millisecondsSinceEpoch;
      var lastChunkTime = startTime;
      var totalBytes = 0;
      chunksStreamController.stream.listen((chunkLength) {
        totalBytes += chunkLength;
        lastChunkTime = DateTime.now().millisecondsSinceEpoch;
      });

      timeoutTimer = Timer(testDuration, () {
        chunksStreamController.close();
        cancelToken.cancel();
      });

      if (onProgress != null) {
        progressTimer = Timer.periodic(args.progressInterval, (timer) {
          final elapsedTime = (lastChunkTime - startTime) / 1000.0;
          final speedMbps = _getMbps(totalBytes, startTime, lastChunkTime);

          onProgress(speedMbps, elapsedTime / testDuration.inSeconds, elapsedTime);

          if (chunksStreamController.isClosed) {
            timer.cancel();
          }
        });
      }

      await Future.wait(tasks.map((task) => pool!.withResource(task)));
      return _getMbps(totalBytes, startTime, lastChunkTime);
    } finally {
      timeoutTimer?.cancel();
      progressTimer?.cancel();
      await pool?.close();

      if (!chunksStreamController.isClosed) {
        chunksStreamController.close();
        cancelToken.cancel();
      }

      httpClient.close(force: true);
    }
  }

  Future<double> testPing(
      {String? url,
      void Function(int ms, double progress, int index)? onProgress,
      int? numberOfPings}) async {
    final testUrl = url ?? _bestServer?.url;
    if (testUrl == null) {
      throw Exception('Not initialized');
    }

    final count = numberOfPings ?? args.numberOfPings;
    final ping = Ping('google.com', count: count);

    final pings = <int>[];

    var index = 0;
    await for (final event in ping.stream) {
      index++;

      if (event.error != null) {
        print('Ping error: ${event.error}');
        continue;
      }

      if (event.response == null || event.response!.time == null) {
        print('Ping error: no response');
        continue;
      }

      final ms = event.response!.time!.inMilliseconds;
      onProgress?.call(ms, (index - 1) / count, (index - 1));

      pings.add(ms);
    }

    return pings.isNotEmpty ? pings.reduce((a, b) => a + b) / pings.length : 0;
  }

  double _getMbps(int totalBytes, int startTime, int endTime) {
    final elapsedTime = (endTime - startTime) / 1000.0;

    return elapsedTime == 0 ? 0 : ((totalBytes * 8) / elapsedTime / 1000000);
  }

  String _buildUserAgent() {
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

  Dio _getHttpClient({bool timeout = true}) {
    return Dio(BaseOptions(
      sendTimeout: timeout ? args.httpTimeout : null,
      connectTimeout: timeout ? args.httpTimeout : null,
      receiveTimeout: timeout ? args.httpTimeout : null,
      headers: {
        'User-Agent': _buildUserAgent(),
        'Cache-Control': 'no-cache',
        'Accept-Encoding': 'gzip',
      },
    ));
  }

  String _buildRequest({required String uri, String bump = '0'}) {
    final delim = uri.contains('?') ? '&' : '?';

    // Add a cache-busting query parameter
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final finalUrl = '$uri${delim}x=$timestamp.$bump';

    return finalUrl;
  }

  Future<void> _getServers() async {
    final httpClient = _getHttpClient();

    try {
      _servers.clear();

      const urls = [
        'https://www.speedtest.net/api/js/servers?engine=js&limit=10&https_functional=true',
      ];

      final config = _config!;

      for (final url in urls) {
        try {
          final uri = Uri.parse(_buildRequest(uri: url));
          final response = await httpClient.getUri(uri);

          if (response.statusCode != 200) {
            throw Exception('HTTP status code: ${response.statusCode}');
          }

          final List<dynamic> servers = response.data;

          for (final server in servers) {
            final id = int.tryParse(server['id'] ?? '');
            if (id == null) continue;

            if (args.server.isNotEmpty && !args.server.contains(id)) {
              continue;
            }

            if (args.exclude.contains(id)) {
              continue;
            }

            try {
              final distance = _calculateDistance(
                config.latLon,
                (
                  double.parse(server['lat'] ?? '0'),
                  double.parse(server['lon'] ?? '0'),
                ),
              );

              if (!_servers.containsKey(distance)) {
                _servers[distance] = [];
              }

              _servers[distance]!.add(SpeedTestServer(
                id: id,
                distance: distance,
                name: server['name'] ?? 'Unknown',
                url: server['url']!,
              ));
            } catch (e) {
              continue;
            }
          }

          if (_servers.isNotEmpty) {
            break;
          }
        } catch (e) {
          print('Error: $e');
          continue;
        }
      }

      if (_servers.isEmpty) {
        throw Exception('No servers found.');
      }
    } finally {
      httpClient.close();
    }
  }

  Future<void> _getBestServer() async {
    final httpClient = _getHttpClient();

    try {
      final closestServers = await _getClosestServers();
      final results = <double, SpeedTestServer>{};

      for (final server in closestServers) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final latencyUrl = '${server.url}/latency.txt?x=$timestamp';
        final latencies = <double>[];

        for (int i = 0; i < 3; i++) {
          final uri = Uri.parse(_buildRequest(uri: '$latencyUrl.$i'));

          try {
            final stopwatch = Stopwatch()..start();
            final response = await httpClient.getUri(uri);
            final latency = stopwatch.elapsedMilliseconds / 1000.0;

            latencies.add(response.statusCode == 200 && response.data.trim() == 'test=test'
                ? latency
                : 3600.0);
          } catch (e) {
            latencies.add(3600.0);
          }
        }

        final avgLatency = (latencies.reduce((a, b) => a + b) / latencies.length) * 1000.0;
        results[avgLatency] = server;
      }

      if (results.isEmpty) {
        throw Exception('Unable to connect to servers to test latency.');
      }

      final bestLatency = results.keys.reduce(min);
      _bestServer = results[bestLatency]!;
    } finally {
      httpClient.close();
    }
  }

  Future<List<SpeedTestServer>> _getClosestServers({limit = 5}) async {
    if (_servers.isNotEmpty) {
      await _getServers();
    }

    final closest = <SpeedTestServer>[];
    final sortedDistances = _servers.keys.toList()..sort();

    for (final distance in sortedDistances) {
      for (final server in _servers[distance]!) {
        closest.add(server);
        if (closest.length == limit) {
          break;
        }
      }

      if (closest.length == limit) {
        break;
      }
    }

    return closest;
  }

  double _calculateDistance((double, double) point1, (double, double) point2) {
    const earthRadius = 6371;
    final dLat = _degreesToRadians(point2.$1 - point1.$1);
    final dLon = _degreesToRadians(point2.$2 - point1.$2);

    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_degreesToRadians(point1.$1)) *
            cos(_degreesToRadians(point2.$1)) *
            (sin(dLon / 2) * sin(dLon / 2));

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180);

  Future<void> _loadConfig() async {
    final httpClient = _getHttpClient();

    try {
      final uri = Uri.parse(_buildRequest(uri: 'https://www.speedtest.net/speedtest-config.php'));

      final response = await httpClient.getUri(uri);

      if (response.statusCode != 200) {
        throw Exception('Failed to retrieve config: ${response.statusCode}');
      }

      final root = XmlDocument.parse(response.data);

      final settingsRoot = root.getElement('settings')!;
      final serverConfig = settingsRoot.getElement('server-config')?.attributes;
      final downloadConfig = settingsRoot.getElement('download')?.attributes;
      final uploadConfig = settingsRoot.getElement('upload')?.attributes;
      final clientConfig = settingsRoot.getElement('client')?.attributes;

      if (serverConfig == null ||
          downloadConfig == null ||
          uploadConfig == null ||
          clientConfig == null) {
        throw Exception('Missing required configuration fields.');
      }

      final ignoreServers = serverConfig
          .where((attr) => attr.name.local == 'ignoreids')
          .map((attr) => attr.value.split(',').map(int.parse).toList())
          .expand((list) => list)
          .toList();

      final uploadMax =
          int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'maxchunkcount').value);

      final sizes = _SpeedTestConfigValues(
        Iterable.generate(100, (i) => 4000).toList(),
        Iterable.generate(100, (i) => (800 * 100 - 51) * 10).toList(),
      );

      final sizeCount = sizes.upload.length;
      final uploadCount = (uploadMax / sizeCount).ceil();

      final counts = _SpeedTestConfigValues(
          int.parse(downloadConfig.firstWhere((attr) => attr.name.local == 'threadsperurl').value),
          int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'threadsperurl').value));

      final threads = _SpeedTestConfigValues(
          int.parse(serverConfig.firstWhere((attr) => attr.name.local == 'threadcount').value) * 2,
          int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'threads').value));

      final length = _SpeedTestConfigValues(
          int.parse(downloadConfig.firstWhere((attr) => attr.name.local == 'testlength').value),
          int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'testlength').value));

      final clientLat =
          double.tryParse(clientConfig.firstWhere((attr) => attr.name.local == 'lat').value);
      final clientLon =
          double.tryParse(clientConfig.firstWhere((attr) => attr.name.local == 'lon').value);

      if (clientLat == null || clientLon == null) {
        throw Exception('Unknown location: lat=$clientLat lon=$clientLon');
      }

      final latLon = (clientLat, clientLon);
      final resultUploadMax = uploadCount * sizeCount;
      _config =
          _SpeedTestConfig(ignoreServers, sizes, counts, threads, length, latLon, resultUploadMax);
    } finally {
      httpClient.close();
    }
  }
}

class SpeedTestServer {
  final int id;
  final double distance;
  final String name;
  final String url;

  SpeedTestServer(
      {required this.id, required this.distance, required this.name, required this.url});
}

class _SpeedTestConfigValues<T> {
  final T download;
  final T upload;

  _SpeedTestConfigValues(this.download, this.upload);
}

class _SpeedTestConfig {
  final List<int> ignoreServers;
  final _SpeedTestConfigValues<List<int>> sizes;
  final _SpeedTestConfigValues<int> counts;
  final _SpeedTestConfigValues<int> threads;
  final _SpeedTestConfigValues<int> length;
  final (double, double) latLon;
  final int uploadMax;

  _SpeedTestConfig(this.ignoreServers, this.sizes, this.counts, this.threads, this.length,
      this.latLon, this.uploadMax);
}

Future<double?> testPing(
    {required String url,
    void Function(int ms, double progress, int index)? onProgress,
    int? numberOfPings}) async {
  if (!_isIosInited && Platform.isIOS) {
    DartPingIOS.register();
    _isIosInited = true;
  }

  final count = numberOfPings ?? 3;
  final ping = Ping(url, count: count);

  final pings = <int>[];

  var index = 0;
  await for (final event in ping.stream) {
    index++;

    if (event.error != null) {
      continue;
    }

    if (event.response == null || event.response!.time == null) {
      continue;
    }

    final ms = event.response!.time!.inMilliseconds;
    onProgress?.call(ms, (index - 1) / count, (index - 1));

    pings.add(ms);
  }

  return pings.isNotEmpty ? pings.reduce((a, b) => a + b) / pings.length : null;
}

var _isIosInited = false;
