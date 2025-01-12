# flutter_network_speed_test

A Flutter library to test network speed, including download, upload, and ping tests. Provides real-time progress and results for each test type.

## Features

- Measure download speed.
- Measure upload speed.
- Measure ping latency.
- Real-time progress updates.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_network_speed_test: ^latest_version
```

Then run:
```yaml
flutter pub get
```

## Usage
1. Wrap Your App with `SpeedTestProvider`

Wrap the part of your app where you need access to the speed test 
functionality in a `SpeedTestProvider`.

```dart
import 'package:flutter_network_speed_test/flutter_network_speed_test.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SpeedTestProvider(
      args: const SpeedTestArgs(duration: Duration(seconds: 10)),
      child: MaterialApp(
        home: SpeedTestScreen(),
      ),
    );
  }
}
```

2. Access `SpeedTestProvider`

Retrieve the SpeedTestProvider state using:
```dart
final speedTest = SpeedTestProvider.of(context);
```

3. Start test
```dart
speedTest.startTest();
```

4. Monitor Progress

Use a StreamBuilder to display real-time test progress.

```dart
StreamBuilder<ProgressData>(
  stream: speedTest.progressStream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      final data = snapshot.data!;
      return Text('${data.type.name}: ${data.speed.toStringAsFixed(2)} Mbps');
    }
    
    return Text('Press start to begin the test.');
  },
);
```

5. Display Results

Access test results after completion.

```dart
final downloadSpeed = speedTest.results[SpeedTestType.download];
final uploadSpeed = speedTest.results[SpeedTestType.upload];
final ping = speedTest.results[SpeedTestType.ping];

Text('Download: ${downloadSpeed.toStringAsFixed(2)} Mbps');
Text('Upload: ${uploadSpeed.toStringAsFixed(2)} Mbps');
Text('Ping: ${ping.toStringAsFixed(2)} ms');
```