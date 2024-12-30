import 'dart:async';
import 'dart:math';

import 'package:flutter_speed_test/flutter_speed_test.dart';
import 'package:flutter_speed_test/src/http_client.dart';
import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:xml/xml.dart';


final class SpeedTest {
  SpeedTest(this.args);

  final SpeedTestArgs args;

  HttpClient? _httpClient;
  _SpeedTestConfig? _config;
  final Map<double, List<SpeedTestServer>> _servers = {};
  SpeedTestServer? _bestServer;
  double? _bestServerLatency;

  Future<void> init() async {
    _httpClient = HttpClient(timeout: Duration(milliseconds: (args.timeout * 1000).floor()));

    await _loadConfig();
    await _getServers();
    await _getBestServer();
  }

  Future<void> testDownloadSpeed() async {
    if (_bestServer == null) {
      throw Exception('Not initialized');
    }

    final List<String> urls = [];
    final httpClient = _httpClient!;
    final downloadSizes = _config!.sizes.download;
    final downloadCounts = _config!.counts.download;
    final maxThreads = _config!.threads.download;

    for (final size in downloadSizes) {
      for (int i = 0; i < downloadCounts; i++) {
        final uri = '${_bestServer!.url}/random${size}x$size.jpg';
        urls.add(uri);
      }
    }

    final requestsUris =
        Iterable.generate(urls.length, (index) => _buildRequest(uri: urls[index], bump: '$index'));

    final chunksStreamController = StreamController<int>();
    final tasks = requestsUris.map((uri) {
      return () async {
        final request = http.Request('GET', Uri.parse(uri));
        final streamedResponse = await httpClient.send(request);

        await for (var chunk in streamedResponse.stream) {
          chunksStreamController.add(chunk.length);
        }
      };
    });

    final pool = Pool(maxThreads);
    final startTime = DateTime.now().millisecondsSinceEpoch;

    var totalBytes = 0;

    chunksStreamController.stream.listen((chunkLength) {
      totalBytes += chunkLength;

      final elapsedTime = (DateTime.now().millisecondsSinceEpoch - startTime) / 1000.0;
      final speedMbps = ((totalBytes * 8) / elapsedTime / 1_000_000).toStringAsFixed(2);

      print('Speed: $speedMbps kbps. Downloaded: $totalBytes bytes. Elapsed: $elapsedTime s.');
    });

  
                Timer.periodic(Duration(milliseconds: 200), (timer) {
    final elapsedTime = (DateTime.now().millisecondsSinceEpoch - startTime) / 1000.0;

    if (elapsedTime > 0) {
      final speedMbps = ((totalBytes * 8) / elapsedTime / 1_000_000).toStringAsFixed(2);
      print('Speed: $speedMbps Mbps. Downloaded: $totalBytes bytes. Elapsed: $elapsedTime s.');
    }

    // Stop the timer when all tasks are done
    if (chunksStreamController.isClosed) {
      timer.cancel();
  }
  });

    await Future.wait(tasks.map((task) => pool.withResource(task)));
  }

  String _buildRequest({required String uri, String bump = '0'}) {
    final delim = uri.contains('?') ? '&' : '?';

    // Add a cache-busting query parameter
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final finalUrl = '$uri${delim}x=$timestamp.$bump';

    return finalUrl;
  }

  Future<void> _getServers() async {
    _servers.clear();

    const urls = [
      'https://www.speedtest.net/speedtest-servers-static.php',
      'http://c.speedtest.net/speedtest-servers-static.php',
      'https://www.speedtest.net/speedtest-servers.php',
      'http://c.speedtest.net/speedtest-servers.php',
    ];

    final config = _config!;
    final httpClient = _httpClient!;

    for (final url in urls) {
      try {
        final uri = Uri.parse(_buildRequest(uri: '$url?threads=${config.threads.download}'));
        final response = await httpClient.get(uri);

        if (response.statusCode != 200) {
          throw Exception('HTTP status code: ${response.statusCode}');
        }

        final root = XmlDocument.parse(response.body);
        final elements = root.findAllElements('server');

        for (final element in elements) {
          final attributesMap = Map.fromEntries(
              element.attributes.map((attr) => MapEntry(attr.name.local, attr.value)));

          final id = int.tryParse(attributesMap['id'] ?? '');
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
                double.parse(attributesMap['lat'] ?? '0'),
                double.parse(attributesMap['lon'] ?? '0'),
              ),
            );
            attributesMap['d'] = distance.toString();

            if (!_servers.containsKey(distance)) {
              _servers[distance] = [];
            }
            _servers[distance]!.add(SpeedTestServer(
              id: id,
              distance: distance,
              name: attributesMap['name'] ?? 'Unknown',
              url: attributesMap['url']!,
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
  }

  Future<void> _getBestServer() async {
    final httpClient = _httpClient!;
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
          final response = await httpClient.get(uri);
          final latency = stopwatch.elapsedMilliseconds / 1000.0;

          latencies.add(
              response.statusCode == 200 && response.body.trim() == 'test=test' ? latency : 3600.0);
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
    _bestServerLatency = bestLatency;
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
    if (_httpClient == null) {
      throw Exception('Client is not initialized');
    }

    final uri = Uri.parse(_buildRequest(uri: 'https://www.speedtest.net/speedtest-config.php'));

    final response = await _httpClient!.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to retrieve config: ${response.statusCode}');
    }

    final root = XmlDocument.parse(response.body);

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

    final ratio = int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'ratio').value);
    final uploadMax =
        int.parse(uploadConfig.firstWhere((attr) => attr.name.local == 'maxchunkcount').value);

    final upSizes = [32768, 65536, 131072, 262144, 524288, 1048576, 7340032];
    final sizes = _SpeedTestConfigValues(
        [350, 500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4000], upSizes.sublist(ratio - 1));

    final sizeCount = sizes.upload.length;
    final uploadCount = (uploadMax / sizeCount).floor();

    final counts = _SpeedTestConfigValues(
        int.parse(downloadConfig.firstWhere((attr) => attr.name.local == 'threadsperurl').value),
        uploadCount);

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

    _config = _SpeedTestConfig(ignoreServers, sizes, counts, threads, length, latLon);
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

  _SpeedTestConfig(
      this.ignoreServers, this.sizes, this.counts, this.threads, this.length, this.latLon);
}