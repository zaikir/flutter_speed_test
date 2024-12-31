import 'package:flutter_speed_test/flutter_speed_test.dart';
import 'package:flutter_speed_test/src/speed_test.dart';

void main() async {
  const args = SpeedTestArgs(duration: Duration(seconds: 5));

  final speedtest = SpeedTest(args);
  await speedtest.init();

  print("inited");

  final mbps = await speedtest.testUploadSpeed(
    onProgress: (mbps, progress, time) {
      print("mbps: $mbps; progress: $progress; time: $time seconds");
    },
  );
  print("mbps: $mbps");
}
