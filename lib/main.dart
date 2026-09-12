import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/hsv_profile.dart';
import 'native/native_cv.dart';
import 'screens/calibrator_screen.dart';
import 'screens/tracker_screen.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error getting cameras: $e');
  }

  // Pre-initialize native FFI engine
  try {
    NativeTracker.instance.initialize();
  } catch (e) {
    debugPrint('Native tracker FFI init error: $e');
  }

  final savedProfile = await HsvProfile.load();

  runApp(BallisticCvApp(
    cameras: _cameras,
    savedProfile: savedProfile,
  ));
}

class BallisticCvApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final HsvProfile? savedProfile;

  const BallisticCvApp({
    super.key,
    required this.cameras,
    this.savedProfile,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BallisticCV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        primaryColor: const Color(0xFF00FF66),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF66),
          secondary: Colors.cyanAccent,
        ),
      ),
      home: savedProfile != null
          ? TrackerScreen(cameras: cameras, hsvProfile: savedProfile!)
          : CalibratorScreen(cameras: cameras),
    );
  }
}
