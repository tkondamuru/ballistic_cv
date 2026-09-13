import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'hsv_profile.dart';

class SampledObject {
  final String id;
  final String name;
  final HsvProfile profile;
  const SampledObject({
    required this.id,
    required this.name,
    required this.profile,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hsv': [
      profile.hMed,
      profile.sMed,
      profile.vMed,
      profile.hMin,
      profile.hMax,
      profile.sMin,
      profile.sMax,
      profile.vMin,
      profile.vMax,
    ],
  };

  factory SampledObject.fromJson(Map<String, dynamic> json) {
    final v = List<int>.from(json['hsv'] as List);
    return SampledObject(
      id: json['id'] as String,
      name: json['name'] as String,
      profile: HsvProfile(
        hMed: v[0],
        sMed: v[1],
        vMed: v[2],
        hMin: v[3],
        hMax: v[4],
        sMin: v[5],
        sMax: v[6],
        vMin: v[7],
        vMax: v[8],
      ),
    );
  }
}

class ObjectLibrary {
  static const key = 'sampled_objects_v1';
  static Future<List<SampledObject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    if (stored != null) {
      return (jsonDecode(stored) as List)
          .map(
            (e) => SampledObject.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    }
    final legacy = await HsvProfile.load();
    final objects = <SampledObject>[
      if (legacy != null)
        SampledObject(id: 'legacy', name: 'Saved ball', profile: legacy),
    ];
    await save(objects);
    return objects;
  }

  static Future<void> save(List<SampledObject> objects) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode(objects.map((e) => e.toJson()).toList()),
    )) {
      throw StateError('Could not save objects');
    }
  }
}
