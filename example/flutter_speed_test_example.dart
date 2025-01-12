import 'package:flutter_network_speed_test/flutter_network_speed_test.dart';

void main() async {
  const args = SpeedTestArgs(duration: Duration(seconds: 1));

  final speedtest = SpeedTest(args);
  await speedtest.init();

  print("inited");

  final downloadSpeed = await speedtest.testUploadSpeed(
    onProgress: (mbps, progress, time) {
      print("mbps: $mbps; progress: $progress; time: $time seconds");
    },
  );
  print("download speed: $downloadSpeed mbps");

  final uploadSpeed = await speedtest.testUploadSpeed(
    onProgress: (mbps, progress, time) {
      print("mbps: $mbps; progress: $progress; time: $time seconds");
    },
  );
  print("upload speed: $uploadSpeed mbps");

  final pingResult = await speedtest.testPing(
    onProgress: (ms, progress, time) {
      print("ms: $ms; progress: $progress; time: $time seconds");
    },
  );
  print("ping: $pingResult ms");
}
