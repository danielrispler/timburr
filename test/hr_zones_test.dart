import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/cardio.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/hr_zones.dart';
import 'package:timburr/data/track.dart';

Track hrTrack(List<int?> hr, {List<int?>? time}) => Track(time: time ?? [for (var i = 0; i < hr.length; i++) i * 10], hr: hr);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('zoneSeconds', () {
    test('splits time into five equal bands from 50% to 100% of Max HR', () {
      // Max 200: bands are 100-120, 120-140, 140-160, 160-180, 180-200. Each sample lasts 10 s until the next.
      expect(zoneSeconds(hrTrack([110, 130, 150, 170, 190, 190]), 200), [10, 10, 10, 10, 10]);
    });
    test('a band edge belongs to the higher zone; below 50% is zone 1 and above 100% zone 5', () {
      expect(zoneSeconds(hrTrack([120, 50, 220, 0]), 200), [10, 10, 0, 0, 10]);
    });
    test('a pause longer than the gap cap adds at most the cap', () {
      expect(zoneSeconds(hrTrack([150, 150, 150], time: [0, 10, 610]), 200)![2], 10 + 30);
    });
    test('samples without HR are skipped; no HR or no time gives null', () {
      expect(zoneSeconds(hrTrack([150, null, 150, 150]), 200)!.fold<double>(0, (a, b) => a + b), 10 + 10);
      expect(zoneSeconds(Track(time: [0, 1]), 200), isNull);
      expect(zoneSeconds(Track(hr: [150, 150]), 200), isNull);
      expect(zoneSeconds(hrTrack([null, null]), 200), isNull);
    });
  });

  test('zonePercents are whole percents of the total', () {
    expect(zonePercents([10, 10, 20, 0, 0]), [25, 25, 50, 0, 0]);
    expect(zonePercents(null), isNull);
    expect(zonePercents([0, 0, 0, 0, 0]), isNull);
  });

  test('Max HR: set value, else 220 minus age, else the default', () {
    final now = DateTime(2026, 11, 21);
    expect(effectiveMaxHr(185, 1990, now), 185);
    expect(effectiveMaxHr(null, 1990, now), 184);
    expect(effectiveMaxHr(null, null, now), defaultMaxHr);
    expect(maxHrFromBirthYear(2026, now), 220);
    expect(maxHrFromBirthYear(1900, now), 100);
  });

  group('SettingsStore', () {
    late AppDb db;
    late CardioStore store;
    setUp(() {
      db = AppDb(NativeDatabase.memory());
      store = CardioStore(db);
    });
    tearDown(() => db.close());

    test('birth year sets Max HR and is remembered; a direct Max HR overrides', () async {
      expect(await store.settings.watch().first, isNull);
      await store.settings.setBirthYear(1990, now: DateTime(2026, 6, 1));
      var s = (await store.settings.watch().first)!;
      expect((s.birthYear, s.maxHr), (1990, 184));
      await store.settings.setMaxHr(180);
      s = (await store.settings.watch().first)!;
      expect((s.birthYear, s.maxHr), (1990, 180));
      expect((s.dirty, s.id), (1, settingsRowId));
    });

    test('Max HR outside 100-250 is refused', () async {
      expect(() => store.settings.setMaxHr(300), throwsArgumentError);
    });

    test('a deleted settings row reads as unset and is revived, without its stale values, on save', () async {
      await store.settings.setBirthYear(1990);
      await db.save(db.appSettings, {'id': settingsRowId, 'deleted_at': DateTime.now()});
      expect(await store.settings.watch().first, isNull);
      await store.settings.setMaxHr(175);
      final s = (await store.settings.watch().first)!;
      expect((s.maxHr, s.birthYear, s.deletedAt), (175, null, null));
    });
  });
}
