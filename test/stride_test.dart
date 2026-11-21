import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/stride.dart';

void main() {
  test('the first correction sets the stride', () {
    final s = calibrateStride(null, 0, 5000, 4.0); // 0.8 m a step
    expect(s.strideM, closeTo(0.8, 1e-9));
    expect(s.samples, 1);
  });

  test('later corrections average with the earlier ones', () {
    var s = calibrateStride(null, 0, 5000, 4.0); // 0.8
    s = calibrateStride(s.strideM, s.samples, 5000, 4.5); // 0.9
    expect(s.strideM, closeTo(0.85, 1e-9));
    expect(s.samples, 2);
  });

  test('a calibrated stride improves the next estimate', () {
    final before = stepDistanceKm(5000, null); // default 1.0 m: 5.0 km
    final s = calibrateStride(null, 0, 5000, 4.0);
    final after = stepDistanceKm(5000, s.strideM);
    expect((after - 4.0).abs(), lessThan((before - 4.0).abs()));
    expect(after, closeTo(4.0, 1e-9));
  });

  test('a correction that cannot be right leaves the stride alone', () {
    for (final (steps, km) in [(0, 4.0), (5000, 0.0), (100, 10.0), (10000, 0.5)]) {
      final s = calibrateStride(0.8, 3, steps, km);
      expect(s.strideM, 0.8);
      expect(s.samples, 3);
    }
  });
}
