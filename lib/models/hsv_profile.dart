import 'package:shared_preferences/shared_preferences.dart';

class HsvProfile {
  final int hMed;
  final int sMed;
  final int vMed;
  final int hMin;
  final int hMax;
  final int sMin;
  final int sMax;
  final int vMin;
  final int vMax;

  const HsvProfile({
    required this.hMed,
    required this.sMed,
    required this.vMed,
    required this.hMin,
    required this.hMax,
    required this.sMin,
    required this.sMax,
    required this.vMin,
    required this.vMax,
  });

  // Default fallback green profile
  static const HsvProfile defaultGreen = HsvProfile(
    hMed: 60,
    sMed: 180,
    vMed: 180,
    hMin: 35,
    hMax: 85,
    sMin: 70,
    sMax: 255,
    vMin: 60,
    vMax: 255,
  );

  static const String _keyHMed = 'hsv_h_med';
  static const String _keySMed = 'hsv_s_med';
  static const String _keyVMed = 'hsv_v_med';
  static const String _keyHMin = 'hsv_h_min';
  static const String _keyHMax = 'hsv_h_max';
  static const String _keySMin = 'hsv_s_min';
  static const String _keySMax = 'hsv_s_max';
  static const String _keyVMin = 'hsv_v_min';
  static const String _keyVMax = 'hsv_v_max';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHMed, hMed);
    await prefs.setInt(_keySMed, sMed);
    await prefs.setInt(_keyVMed, vMed);
    await prefs.setInt(_keyHMin, hMin);
    await prefs.setInt(_keyHMax, hMax);
    await prefs.setInt(_keySMin, sMin);
    await prefs.setInt(_keySMax, sMax);
    await prefs.setInt(_keyVMin, vMin);
    await prefs.setInt(_keyVMax, vMax);
  }

  static Future<HsvProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyHMin)) return null;

    return HsvProfile(
      hMed: prefs.getInt(_keyHMed) ?? 60,
      sMed: prefs.getInt(_keySMed) ?? 180,
      vMed: prefs.getInt(_keyVMed) ?? 180,
      hMin: prefs.getInt(_keyHMin) ?? 35,
      hMax: prefs.getInt(_keyHMax) ?? 85,
      sMin: prefs.getInt(_keySMin) ?? 70,
      sMax: prefs.getInt(_keySMax) ?? 255,
      vMin: prefs.getInt(_keyVMin) ?? 60,
      vMax: prefs.getInt(_keyVMax) ?? 255,
    );
  }
}
