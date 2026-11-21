import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/strava_tcx.dart';

typedef Pt = (String time, double dist, (double, double)? pos, int? hr);

/// A TCX modelled on Strava's export: laps hold trackpoints, and the distance restarts at 0 in each lap.
String tcx(List<List<Pt>> laps, {String id = '2026-11-16T18:02:51.354Z'}) {
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"><Activities><Activity Sport="Running"><Id>$id</Id>');
  for (final lap in laps) {
    b.write('<Lap StartTime="${lap.first.$1}"><Track>');
    for (final (time, dist, pos, hr) in lap) {
      b.write('<Trackpoint><Time>$time</Time>');
      if (pos != null) b.write('<Position><LatitudeDegrees>${pos.$1}</LatitudeDegrees><LongitudeDegrees>${pos.$2}</LongitudeDegrees></Position><AltitudeMeters>20.5</AltitudeMeters>');
      b.write('<DistanceMeters>$dist</DistanceMeters>');
      if (hr != null) b.write('<HeartRateBpm><Value>$hr.0</Value></HeartRateBpm>');
      b.write('</Trackpoint>');
    }
    b.write('</Track><DistanceMeters>${lap.last.$2}</DistanceMeters><TotalTimeSeconds>600.0</TotalTimeSeconds></Lap>');
  }
  b.write('</Activity></Activities></TrainingCenterDatabase>');
  return b.toString();
}

/// [n] one-second points 3 m apart starting [t0] seconds past 18:00:00Z, with positions when [gps].
List<Pt> points(int n, {bool gps = true, int t0 = 0, int? hr, int day = 16}) => [
      for (var i = 0; i < n; i++)
        (DateTime.utc(2026, 11, day, 18, 0, t0 + i).toIso8601String(), i * 3.0, gps ? (32.0 + i * 0.00003, 34.8) : null, hr),
    ];

const run = '2026-11-16T20_00_00.5+02_00_PT8M48.297S_ריצה.tcx';

void main() {
  test('Moving time comes from the file name, with fractional seconds', () {
    final r = parseStravaTcx(run, tcx([points(60)])).recording!;
    expect(r.movingSec, 528);
    expect(r.type, 'run');
    expect(r.source, 'file');
  });

  test('Elapsed time and distance come from the track and laps, not the name', () {
    final r = parseStravaTcx(run, tcx([points(60)])).recording!;
    expect(r.start, DateTime.utc(2026, 11, 16, 18));
    expect(r.elapsedSec, 59);
    expect(r.distanceKm, closeTo(0.177, 1e-9));
  });

  test('laps restart the distance, so the totals add up and the track runs on', () {
    final r = parseStravaTcx(run, tcx([points(60), points(60, t0: 70)])).recording!;
    expect(r.distanceKm, closeTo(0.354, 1e-9));
    final d = r.track!.distance!;
    expect(d.length, 120);
    expect(d[59], 177);
    expect(d[60], closeTo(177, 1e-9)); // the second lap starts where the first ended
    expect(d.last, closeTo(354, 1e-9));
    expect(r.track!.time!.last, 129);
  });

  test('type labels', () {
    String type(String label) => parseStravaTcx('2026-11-16T20_00_00+02_00_PT8M48S_$label.tcx', tcx([points(60)])).recording!.type;
    expect(type('ריצה'), 'run');
    expect(type('ריצה על הליכון'), 'treadmill');
    final walk = parseStravaTcx('2026-11-16T20_00_00+02_00_PT8M48S_ריצה,הליכה.tcx', tcx([points(60)])).recording!;
    expect(walk.type, 'run');
    expect(walk.notes, 'run/walk');
  });

  test('a full track keeps its route, heart rate and altitude', () {
    final r = parseStravaTcx(run, tcx([points(60, hr: 150)])).recording!;
    expect(r.hasRoute, isTrue);
    expect(r.track!.hr!.first, 150);
    expect(r.track!.altitude!.first, 20.5);
    expect(r.avgHr, 150);
    expect(r.maxHr, 150);
  });

  test('under 50 points the Run has distance and time but no route', () {
    final p = parseStravaTcx(run, tcx([points(40)]));
    expect(p.recording!.hasRoute, isFalse);
    expect(p.recording!.track!.lat, isNull);
    expect(p.recording!.distanceKm, closeTo(0.117, 1e-9));
    expect(p.warnings, contains(contains('route')));
  });

  test('a treadmill file has no GPS and no route', () {
    final r = parseStravaTcx('2026-11-16T20_00_00+02_00_PT8M48S_ריצה על הליכון.tcx', tcx([points(300, gps: false, hr: 140)])).recording!;
    expect(r.type, 'treadmill');
    expect(r.hasRoute, isFalse);
    expect(r.track!.hr!.length, 300);
  });

  test('zero distance is skipped with a reason', () {
    final p = parseStravaTcx(run, tcx([
      [for (var i = 0; i < 4; i++) (DateTime.utc(2026, 9, 28, 15, i).toIso8601String(), 0.0, null, null)],
    ]));
    expect(p.recording, isNull);
    expect(p.skipReason, contains('distance'));
  });

  test('a name without Moving time falls back to the lap times, with a warning', () {
    final p = parseStravaTcx('mystery.tcx', tcx([points(60)]));
    expect(p.recording!.movingSec, 600); // the lap's TotalTimeSeconds
    expect(p.warnings, contains(contains('Moving time')));
  });

  test('the Activity Id is the external id, so the same file is the same recording', () {
    expect(parseStravaTcx(run, tcx([points(60)])).recording!.externalId, '2026-11-16T18:02:51.354Z');
  });

  test('text that is not a TCX is skipped', () {
    expect(parseStravaTcx(run, 'not xml at all').skipReason, isNotNull);
    expect(parseStravaTcx('x.gpx', '<gpx/>').skipReason, isNotNull);
  });
}
