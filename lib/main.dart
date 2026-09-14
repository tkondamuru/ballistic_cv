import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'native/native_cv.dart';
import 'screens/home_screen.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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

  runApp(BallisticCvApp(cameras: _cameras));
}

class BallisticCvApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const BallisticCvApp({super.key, required this.cameras});

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
      home: HomeScreen(cameras: cameras),
    );
  }
}
