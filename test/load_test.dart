import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/load.dart';
import 'package:timburr/data/track.dart';

CardioData run(DateTime at, {int sec = 1800, int? avgHr, String type = 'run'}) => CardioData(
    id: '$at', createdAt: DateTime(2026), updatedAt: DateTime(2026), dirty: 0, editedFields: const [],
    type: type, startedAt: at, durationSec: sec, avgHr: avgHr);

Track hrTrack(List<int> hr, {int step = 60}) => Track(time: [for (var i = 0; i < hr.length; i++) i * step], hr: hr);

void main() {
  group('relativeEffort', () {
    test('is minutes in each zone times the zone number', () {
      // 10 min in zone 1, 20 in zone 3, 5 in zone 5.
      expect(relativeEffort([600, 0, 1200, 0, 300]), 10 * 1 + 20 * 3 + 5 * 5);
    });
    test('no time in zones gives null', () => expect(relativeEffort(null), isNull));
  });

  group('runLoad', () {
    test('a Run with an HR track scores from its time in zones and is not an estimate', () {
      // Max 200; 150 bpm is zone 3; 11 samples a minute apart = 10 minutes.
      final l = runLoad(run(DateTime(2026, 11, 1)), hrTrack(List.filled(21, 150), step: 30), 200);
      expect(l.effort, closeTo(30, 1e-9));
      expect(l.estimated, isFalse);
    });
    test('without a track but with an average HR, the whole Moving time is in that zone', () {
      final l = runLoad(run(DateTime(2026, 11, 1), sec: 1200, avgHr: 170), null, 200); // zone 4, 20 min
      expect(l.effort, closeTo(80, 1e-9));
      expect(l.estimated, isFalse);
    });
    test('without any HR the Run is estimated as an easy Run: Moving time in zone 2', () {
      final l = runLoad(run(DateTime(2026, 11, 1), sec: 1800), null, 200);
      expect(l.effort, closeTo(60, 1e-9));
      expect(l.estimated, isTrue);
    });
  });

  group('fitnessSeries', () {
    final d0 = DateTime(2026, 11, 1);
    test('one Run lifts Fitness by load/42 and Fatigue by load/7, Form is their difference', () {
      final s = fitnessSeries([(d0, 420.0)], d0, d0);
      expect(s.single.fitness, closeTo(10, 1e-9));
      expect(s.single.fatigue, closeTo(60, 1e-9));
      expect(s.single.form, closeTo(-50, 1e-9));
    });
    test('rest days decay both curves; Fatigue falls faster so Form turns positive', () {
      final s = fitnessSeries([(d0, 420.0)], d0, DateTime(2026, 11, 3));
      expect(s.length, 3);
      expect(s[1].fitness, closeTo(10 * (1 - 1 / 42), 1e-9));
      expect(s[1].fatigue, closeTo(60 * (1 - 1 / 7), 1e-9));
      final late = fitnessSeries([(d0, 420.0)], d0, DateTime(2026, 12, 31)).last;
      expect(late.form, greaterThan(0));
    });
    test('Runs on the same day add up, and load before the window still counts', () {
      final a = fitnessSeries([(d0, 100.0), (DateTime(2026, 11, 1, 18), 100.0)], d0, d0);
      expect(a.single.fatigue, closeTo(200 / 7, 1e-9));
      final b = fitnessSeries([(d0, 420.0)], DateTime(2026, 11, 2), DateTime(2026, 11, 2));
      expect(b.single.fitness, closeTo(10 * (1 - 1 / 42), 1e-9));
      expect(b.single.day, DateTime(2026, 11, 2));
    });
    test('no Runs gives flat zeros', () {
      expect(fitnessSeries([], d0, DateTime(2026, 11, 3)).map((p) => p.fitness), [0, 0, 0]);
    });
  });
}
