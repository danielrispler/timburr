import 'run_analysis.dart';
import 'track.dart';

/// Fewer positioned points than this and a recording has no route (old Strava files have a handful).
const minRoutePoints = 50;

/// How many points have both a latitude and a longitude. The one rule for "enough to draw a route" is [minRoutePoints] of these.
int positionedCount(List<double?>? lat, List<double?>? lon) => _positioned(lat, lon).length;

List<int> _positioned(List<double?>? lat, List<double?>? lon) =>
    lat == null || lon == null ? const [] : [for (var i = 0; i < lat.length && i < lon.length; i++) if (lat[i] != null && lon[i] != null) i];

/// Everything one source knows about a stretch of running. Every source (file, Health Connect, live recording) hands one to `CardioStore.ingest`.
class Recording {
  Recording({
    required this.source,
    required this.type,
    required this.start,
    required this.elapsedSec,
    this.movingSec,
    this.externalId,
    this.distanceKm,
    this.track,
    this.avgHr,
    this.maxHr,
    this.calories,
    this.avgCadence,
    this.elevationGainM,
    this.notes,
  });

  final String source; // file, health_connect or recorded
  final String type; // run or treadmill
  final DateTime start;
  final int elapsedSec; // start to end, pauses included
  final int? movingSec; // null when the source has none: [moving] then comes from the track
  final String? externalId; // with source, identifies the recording so ingesting it twice changes nothing
  final double? distanceKm;
  final Track? track;
  final int? avgHr, maxHr, calories;
  final double? avgCadence, elevationGainM;
  final String? notes;

  /// The route stored on the Run for thumbnails: [simplifyRoute] of the track, null when there is no route.
  String? get route => hasRoute ? simplifyRoute(track!) : null;

  /// Moving time: the source's, else auto-pause over the track, else Elapsed time.
  int get moving => movingSec ?? (track == null ? null : autoPauseMovingSec(track!)) ?? elapsedSec;

  /// Elevation gain: the source's, else the climb over the track's altitudes.
  double? get elevation => elevationGainM ?? (track == null ? null : elevationGain(track!));

  DateTime get end => start.add(Duration(seconds: elapsedSec));

  /// True when the track has enough positioned points to draw a map.
  bool get hasRoute => track != null && positionedCount(track!.lat, track!.lon) >= minRoutePoints;
}

/// About [points] evenly spaced positions of [t] as `lat,lon;lat,lon;...` (5 decimals, about 1 m), first and last included. Null when [t] has no route.
String? simplifyRoute(Track t, {int points = 200}) {
  final lat = t.lat, lon = t.lon, idx = _positioned(lat, lon);
  if (idx.length < minRoutePoints) return null;
  final picked = idx.length <= points ? idx : [for (var k = 0; k < points; k++) idx[(k * (idx.length - 1) / (points - 1)).round()]];
  return picked.map((i) => '${lat![i]!.toStringAsFixed(5)},${lon![i]!.toStringAsFixed(5)}').join(';');
}
