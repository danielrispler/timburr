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

/// Turns parsed points into a [Recording] (source `file`) using the Strava file-name rules, shared by the TCX and GPX readers. [distanceM] is the total.
ParsedFile buildRunFile(String fileName, String externalId,
    {required List<DateTime> time, required List<double?> dist, required List<double?> lat, required List<double?> lon, required List<double?> alt, required List<int?> hr, required double distanceM}) {
  final name = fileName.split('/').last;
  final warnings = <String>[];
  if (time.isEmpty) return ParsedFile(name, skipReason: 'No track points');
  if (distanceM <= 0) return ParsedFile(name, skipReason: 'No distance recorded');

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
  final moving = m == null ? null : _movingFromName(m);
  if (moving == null) {
    warnings.add('No Moving time in the file name, so it comes from the track with auto-pause');
  }

  final positioned = positionedCount(lat, lon);
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
        distanceKm: distanceM / 1000,
        track: track,
        avgHr: hrs.isEmpty ? null : (hrs.reduce((a, b) => a + b) / hrs.length).round(),
        maxHr: hrs.isEmpty ? null : hrs.reduce((a, b) => a > b ? a : b),
        notes: notes,
      ));
}
