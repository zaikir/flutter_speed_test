import 'package:flutter_speed_test/flutter_speed_test.dart';
import 'package:flutter_speed_test/src/speed_test.dart';

void main() async {
  const args = SpeedTestArgs();

  final quiet = args.simple || args.csv || args.json;
  final machineFormat = args.csv || args.json;

  final speedtest = SpeedTest(args);
  await speedtest.init();

  final mbps = await speedtest.testDownloadSpeed();
  print("mbps: $mbps");
}
