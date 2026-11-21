import 'package:xml/xml.dart';

import 'recording.dart';
import 'track.dart';

/// The outcome of reading one file: a [recording], or a [skipReason]. [warnings] are worth showing either way.
class ParsedFile {
  ParsedFile(this.name, {this.recording, this.skipReason, this.warnings = const []});
  final String name;
  final Recording? recording;
  final String? skipReason;
  final List<String> warnings;
}

// Strava names a file `2026-10-24T17_17_39.5+03_00_PT13M33.4S_<label>.tcx`: local start, Moving time, type label.
final _name = RegExp(r'^\d{4}-\d\d-\d\dT[\d_.]+[+-]\d\d_\d\d_PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?_(.+)\.(?:tcx|gpx)$', caseSensitive: false);

/// Moving time in seconds from a Strava file name, or null when the name carries none.
int? _movingFromName(RegExpMatch m) {
  if (m[1] == null && m[2] == null && m[3] == null) return null;
  final sec = (int.tryParse(m[1] ?? '0') ?? 0) * 3600 + (int.tryParse(m[2] ?? '0') ?? 0) * 60 + (double.tryParse(m[3] ?? '0') ?? 0);
  return sec.round();
}

/// Reads a Strava TCX export into a [Recording] (source `file`). Lap totals include pauses, so Moving time comes from the file name.
ParsedFile parseStravaTcx(String fileName, String xml) {
  final name = fileName.split('/').last;
  if (!name.toLowerCase().endsWith('.tcx')) return ParsedFile(name, skipReason: 'Not a TCX file');
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return ParsedFile(name, skipReason: 'Not readable as TCX');
  }
  final activity = doc.findAllElements('Activity').firstOrNull;
  if (activity == null) return ParsedFile(name, skipReason: 'No activity in the file');

  String? text(XmlElement e, String tag) => e.getElement(tag)?.innerText.trim();

  // Strava restarts the trackpoint distance in every lap; the track runs on from the previous lap's end.
  final time = <DateTime>[], dist = <double?>[], lat = <double?>[], lon = <double?>[], alt = <double?>[], hr = <int?>[];
  var offset = 0.0, lapSeconds = 0.0;
  for (final lap in activity.findElements('Lap')) {
    var lapEnd = 0.0;
    for (final tp in lap.findAllElements('Trackpoint')) {
      final t = DateTime.tryParse(text(tp, 'Time') ?? '');
      if (t == null) continue;
      final d = double.tryParse(text(tp, 'DistanceMeters') ?? '');
      final pos = tp.getElement('Position');
      time.add(t);
      dist.add(d == null ? null : offset + d);
      lat.add(pos == null ? null : double.tryParse(text(pos, 'LatitudeDegrees') ?? ''));
      lon.add(pos == null ? null : double.tryParse(text(pos, 'LongitudeDegrees') ?? ''));
      alt.add(double.tryParse(text(tp, 'AltitudeMeters') ?? ''));
      final v = tp.getElement('HeartRateBpm')?.getElement('Value')?.innerText.trim();
      hr.add(v == null ? null : double.tryParse(v)?.round());
      if (d != null && d > lapEnd) lapEnd = d;
    }
    offset += double.tryParse(text(lap, 'DistanceMeters') ?? '') ?? lapEnd;
    lapSeconds += double.tryParse(text(lap, 'TotalTimeSeconds') ?? '') ?? 0;
  }
  return buildRunFile(name, text(activity, 'Id') ?? name, time: time, dist: dist, lat: lat, lon: lon, alt: alt, hr: hr, distanceM: offset, lapSeconds: lapSeconds);
}

/// Turns parsed points into a [Recording] (source `file`) using the Strava file-name rules, shared by the TCX and GPX readers. [distanceM] is the total, [lapSeconds] the fallback Moving time.
ParsedFile buildRunFile(String fileName, String externalId,
    {required List<DateTime> time, required List<double?> dist, required List<double?> lat, required List<double?> lon, required List<double?> alt, required List<int?> hr, required double distanceM, double lapSeconds = 0}) {
  final name = fileName.split('/').last;
  final warnings = <String>[];
  final offset = distanceM;
  if (time.isEmpty) return ParsedFile(name, skipReason: 'No track points');
  if (offset <= 0) return ParsedFile(name, skipReason: 'No distance recorded');

  final start = time.reduce((a, b) => a.isBefore(b) ? a : b), end = time.reduce((a, b) => a.isAfter(b) ? a : b);
  final elapsed = end.difference(start).inSeconds;

  final m = _name.firstMatch(name);
  var type = 'run';
  String? notes;
  if (m == null) {
    warnings.add('Not a Strava file name, so type is Run');
  } else {
    switch (m[4]!.trim()) {
      case 'ריצה':
        break;
      case 'ריצה על הליכון':
        type = 'treadmill';
      case 'ריצה,הליכה':
        notes = 'run/walk';
      default:
        warnings.add('Unknown type "${m[4]}", saved as Run');
    }
  }
  var moving = m == null ? null : _movingFromName(m);
  if (moving == null) {
    moving = lapSeconds > 0 ? lapSeconds.round() : elapsed;
    warnings.add('No Moving time in the file name, using ${lapSeconds > 0 ? 'the lap times' : 'Elapsed time'}');
  }

  final positioned = [for (var i = 0; i < lat.length; i++) if (lat[i] != null && lon[i] != null) i].length;
  final hasRoute = positioned >= minRoutePoints;
  if (type == 'run' && !hasRoute) {
    warnings.add(positioned == 0 ? 'No GPS, so no route' : 'Only $positioned GPS points, so no route');
  }
  final hrs = [for (final v in hr) ?v];
  final track = Track(
    time: [for (final t in time) t.difference(start).inSeconds],
    distance: dist,
    lat: hasRoute ? lat : null,
    lon: hasRoute ? lon : null,
    altitude: alt.any((v) => v != null) ? alt : null,
    hr: hrs.isEmpty ? null : hr,
  );
  return ParsedFile(name,
      warnings: warnings,
      recording: Recording(
        source: 'file',
        externalId: externalId,
        type: type,
        start: start,
        elapsedSec: elapsed,
        movingSec: moving,
        distanceKm: offset / 1000,
        track: track,
        avgHr: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
        maxHr: hrs.isEmpty ? null : hrs.reduce((a, b) => a > b ? a : b),
        notes: notes,
      ));
}
