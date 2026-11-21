import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/track.dart';

void main() {
  test('a full track survives encode and decode', () {
    final t = Track(
      time: [0, 5, 10],
      distance: [0, 14.2, 29.75],
      lat: [32.0853, 32.08535, 32.0854],
      lon: [34.7818, 34.78185, 34.7819],
      altitude: [20.5, 21.0, 21.5],
      hr: [120, 125, 131],
      cadence: [82, 84, 85],
    );
    final back = Track.decode(t.encode());
    expect(back.time, [0, 5, 10]);
    expect(back.distance, [0, 14.2, 29.75]);
    expect(back.lat, t.lat);
    expect(back.lon, t.lon);
    expect(back.altitude, [20.5, 21.0, 21.5]);
    expect(back.hr, [120, 125, 131]);
    expect(back.cadence, [82, 84, 85]);
  });

  test('absent columns stay null, and a gap inside a column stays null', () {
    final back = Track.decode(Track(time: [0, 5, 10], distance: [0, 10, 20], hr: [null, 130, null]).encode());
    expect(back.lat, isNull);
    expect(back.altitude, isNull);
    expect(back.cadence, isNull);
    expect(back.hr, [null, 130, null]);
    expect(back.length, 3);
  });

  test('the encoding is base64 text and shrinks a long track', () {
    const n = 3000;
    final t = Track(time: [for (var i = 0; i < n; i++) i], distance: [for (var i = 0; i < n; i++) i * 2.8], hr: [for (var i = 0; i < n; i++) 140 + i % 7]);
    final s = t.encode();
    expect(RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(s), isTrue);
    expect(s.length, lessThan(n * 8));
    expect(Track.decode(s).hr, t.hr);
  });

  test('ids are deterministic per Run and distinct from each other', () {
    expect(trackRowId('c1'), trackRowId('c1'));
    expect(trackRowId('c1'), isNot(trackRowId('c2')));
  });
}
