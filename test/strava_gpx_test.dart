import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/strava_gpx.dart';
import 'package:timburr/data/strava_import.dart';
import 'package:timburr/data/strava_tcx.dart';

const name = '2026-11-16T20_00_00.5+02_00_PT8M48.297S_ריצה';
const id = '2026-11-16T18:00:00Z';
const step = 111194.9266 * 0.00003; // metres between points 0.00003 degrees of latitude apart

String _t(int i) => DateTime.utc(2026, 11, 16, 18, 0, i).toIso8601String();
int _hr(int i) => 140 + i % 5;

/// The same [n]-point track as a GPX (Strava style, Garmin hr extension) and as a TCX.
String gpx(int n) => '<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"><metadata><time>$id</time></metadata><trk><name>Run</name><trkseg>'
    '${[for (var i = 0; i < n; i++) '<trkpt lat="${32.0 + i * 0.00003}" lon="34.8"><ele>20.5</ele><time>${_t(i)}</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>${_hr(i)}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>'].join()}'
    '</trkseg></trk></gpx>';

String tcx(int n) => '<TrainingCenterDatabase><Activities><Activity Sport="Running"><Id>$id</Id><Lap StartTime="${_t(0)}"><Track>'
    '${[for (var i = 0; i < n; i++) '<Trackpoint><Time>${_t(i)}</Time><Position><LatitudeDegrees>${32.0 + i * 0.00003}</LatitudeDegrees><LongitudeDegrees>34.8</LongitudeDegrees></Position><AltitudeMeters>20.5</AltitudeMeters><DistanceMeters>${i * step}</DistanceMeters><HeartRateBpm><Value>${_hr(i)}</Value></HeartRateBpm></Trackpoint>'].join()}'
    '</Track><DistanceMeters>${(n - 1) * step}</DistanceMeters><TotalTimeSeconds>${n - 1}</TotalTimeSeconds></Lap></Activity></Activities></TrainingCenterDatabase>';

void main() {
  test('a GPX gives the same Recording as the equivalent TCX', () {
    final g = parseStravaGpx('$name.gpx', gpx(60)).recording!;
    final t = parseStravaTcx('$name.tcx', tcx(60)).recording!;
    expect(g.source, t.source);
    expect(g.externalId, t.externalId);
    expect(g.type, t.type);
    expect(g.start, t.start);
    expect(g.elapsedSec, t.elapsedSec);
    expect(g.movingSec, 528);
    expect(g.movingSec, t.movingSec);
    expect(g.distanceKm, closeTo(t.distanceKm!, 1e-4));
    expect(g.avgHr, t.avgHr);
    expect(g.maxHr, t.maxHr);
    expect(g.hasRoute, isTrue);
    expect(g.track!.time, t.track!.time);
    expect(g.track!.lat, t.track!.lat);
    expect(g.track!.lon, t.track!.lon);
    expect(g.track!.altitude, t.track!.altitude);
    expect(g.track!.hr, t.track!.hr);
    for (var i = 0; i < 60; i++) {
      expect(g.track!.distance![i]!, closeTo(t.track!.distance![i]!, 0.01));
    }
  });

  test('Strava file-name rules apply to GPX', () {
    final r = parseStravaGpx('2026-11-16T20_00_00+02_00_PT8M48S_ריצה על הליכון.gpx', gpx(60)).recording!;
    expect(r.type, 'treadmill');
    expect(r.movingSec, 528);
    expect(parseStravaGpx('2026-11-16T20_00_00+02_00_PT8M48S_ריצה,הליכה.gpx', gpx(60)).recording!.notes, 'run/walk');
    final plain = parseStravaGpx('morning.gpx', gpx(60));
    expect(plain.warnings, isNotEmpty);
    expect(plain.recording!.moving, 59);
  });

  test('a short track keeps distance and time but no route', () {
    final r = parseStravaGpx('$name.gpx', gpx(20)).recording!;
    expect(r.hasRoute, isFalse);
    expect(r.distanceKm!, greaterThan(0));
  });

  test('bad files are skipped with a reason', () {
    expect(parseStravaGpx('$name.tcx', gpx(60)).skipReason, isNotNull);
    expect(parseStravaGpx('$name.gpx', 'nope').skipReason, isNotNull);
    expect(parseStravaGpx('$name.gpx', '<gpx><trk><trkseg/></trk></gpx>').skipReason, isNotNull);
  });

  test('parseRunFile picks the parser by extension', () {
    expect(parseRunFile('$name.gpx', gpx(60)).recording, isNotNull);
    expect(parseRunFile('$name.tcx', tcx(60)).recording, isNotNull);
    expect(parseRunFile('$name.gpx', tcx(60)).recording, isNull);
  });
}
