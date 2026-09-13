import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ballistic_cv/models/hsv_profile.dart';
import 'package:ballistic_cv/models/sampled_object.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('saved objects survive reload and deletion', () async {
    const a = SampledObject(
      id: 'a',
      name: 'Orange ball',
      profile: HsvProfile.defaultGreen,
    );
    const b = SampledObject(
      id: 'b',
      name: 'Second ball',
      profile: HsvProfile.defaultGreen,
    );
    await ObjectLibrary.save([a, b]);
    var loaded = await ObjectLibrary.load();
    expect(loaded.map((e) => e.name), ['Orange ball', 'Second ball']);
    expect(loaded.first.profile.hMin, a.profile.hMin);
    await ObjectLibrary.save([loaded.last]);
    loaded = await ObjectLibrary.load();
    expect(loaded.single.id, 'b');
  });
  test(
    'migrates old profile once and does not resurrect a deleted object',
    () async {
      await HsvProfile.defaultGreen.save();
      final loaded = await ObjectLibrary.load();
      expect(loaded.single.name, 'Saved ball');
      await ObjectLibrary.save([]);
      expect(await ObjectLibrary.load(), isEmpty);
    },
  );
}
