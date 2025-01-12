import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_network_speed_test/flutter_network_speed_test.dart';

class SpeedTestProvider extends StatefulWidget {
  final Widget child;
  final SpeedTestArgs args;
  final SpeedTest _speedTest;

  SpeedTestProvider({super.key, required this.child, this.args = const SpeedTestArgs()})
      : _speedTest = SpeedTest(args);

  @override
  State<SpeedTestProvider> createState() => SpeedTestProviderState();

  static SpeedTestProviderState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_InheritedSpeedTest>()!.state;
  }

  static SpeedTestProviderState get(BuildContext context) {
    return context.getInheritedWidgetOfExactType<_InheritedSpeedTest>()!.state;
  }
}

enum SpeedTestType { download, upload, ping }

class ProgressData {
  final SpeedTestType type;
  final double progress;
  final double speed;
  final double time;

  ProgressData(this.type, this.progress, this.speed, this.time);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;

    return other is ProgressData &&
        other.type == type &&
        other.progress == progress &&
        other.speed == speed &&
        other.time == time;
  }

  @override
  int get hashCode => Object.hash(type, progress, speed, time);
}

class SpeedTestProviderState extends State<SpeedTestProvider> {
  Future<void>? _initializationFuture;
  bool isTesting = false;
  Stream<ProgressData>? progressStream;
  Map<SpeedTestType, double?> results = {
    SpeedTestType.download: null,
    SpeedTestType.upload: null,
    SpeedTestType.ping: null
  };

  @override
  void initState() {
    super.initState();

    _initializationFuture = widget._speedTest.init();
  }

  Future<void> startTest({download = true, upload = true}) async {
    if (isTesting) {
      return;
    }

    try {
      var progressController = StreamController<ProgressData>.broadcast();

      setState(() {
        isTesting = true;
        results = {
          SpeedTestType.download: null,
          SpeedTestType.upload: null,
          SpeedTestType.ping: null
        };
        progressStream = progressController.stream;
      });

      await _initializationFuture;

      if (widget._speedTest.args.download) {
        final downloadSpeed = await widget._speedTest.testDownloadSpeed(
            onProgress: (double mbps, double progress, double time) {
          progressController.add(ProgressData(SpeedTestType.download, progress, mbps, time));
        });

        setState(() {
          results[SpeedTestType.download] = downloadSpeed;
        });
      }

      if (widget._speedTest.args.upload) {
        final uploadSpeed = await widget._speedTest.testUploadSpeed(
            onProgress: (double mbps, double progress, double time) {
          progressController.add(ProgressData(SpeedTestType.upload, progress, mbps, time));
        });

        setState(() {
          results[SpeedTestType.upload] = uploadSpeed;
        });
      }

      if (!widget._speedTest.args.ping) {
        final ping =
            await widget._speedTest.testPing(onProgress: (int ms, double progress, int index) {
          progressController
              .add(ProgressData(SpeedTestType.ping, progress, ms.toDouble(), index.toDouble()));
        });

        setState(() {
          results[SpeedTestType.ping] = ping;
        });
      }

      progressController.close();
    } catch (e) {
      print(e);
    } finally {
      setState(() {
        progressStream = null;
        isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedSpeedTest(
      state: this,
      child: widget.child,
    );
  }
}

class _InheritedSpeedTest extends InheritedWidget {
  final SpeedTestProviderState state;

  const _InheritedSpeedTest({
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_InheritedSpeedTest oldWidget) {
    return true;
  }
}
