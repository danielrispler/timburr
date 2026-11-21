import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/best_efforts.dart';
import 'package:timburr/data/predictor.dart';

void main() {
  final now = DateTime.utc(2026, 6, 1);
  Effort eff(int d, double s, {int daysAgo = 10}) => (cardioId: 'a', distanceM: d, seconds: s, startedAt: now.subtract(Duration(days: daysAgo)));

  test('Riegel scales time by the distance ratio to the power 1.06', () {
    // 20:00 for 5 km -> 10 km: 1200 * 2^1.06 = 2501.9 s
    expect(riegel(1200, 5000, 10000), closeTo(2501.9, 0.5));
    expect(riegel(1200, 5000, 5000), 1200);
  });

  test('a recent 5 km effort predicts 5 km, 10 km and the half marathon', () {
    final p = predictRaces([eff(5000, 1200)], now);
    expect([for (final r in p) r.distanceM], [5000, 10000, 21098]);
    expect(p[0].seconds, 1200);
    expect(p[1].seconds, closeTo(2501.9, 0.5));
    expect(p[2].seconds, closeTo(5520, 5)); // 1200 * (21097.5 / 5000)^1.06
  });

  test('the best prediction across recent efforts wins', () {
    final p = predictRaces([eff(5000, 1200), eff(10000, 2400)], now);
    final ten = p.firstWhere((r) => r.distanceM == 10000);
    expect(ten.seconds, 2400); // beats the 2502 s predicted from the 5 km
    expect(ten.fromDistanceM, 10000);
  });

  test('efforts older than the window do not count', () => expect(predictRaces([eff(5000, 1200, daysAgo: 200)], now), isEmpty));

  test('efforts shorter than a mile say too little about a race', () {
    expect(predictRaces([eff(400, 70), eff(1000, 240)], now), isEmpty);
  });

  test('a mile effort predicts the 5 km only', () {
    final p = predictRaces([eff(1609, 420)], now);
    expect([for (final r in p) r.distanceM], [5000]);
  });

  test('no efforts, no predictions', () => expect(predictRaces(const [], now), isEmpty));
}
