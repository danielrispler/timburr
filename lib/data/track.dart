import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:uuid/uuid.dart';

const _trackNamespace = '7a1e5d52-3b0c-5f1a-8c2e-9d4b6a7c8e01';

/// Deterministic `cardio_tracks` id of a Run, so two offline devices agree (one track per Run).
String trackRowId(String cardioId) => const Uuid().v5(_trackNamespace, cardioId);

/// Id of the one `settings` row. Fixed, so every device and a restore into a fresh project agree.
final settingsRowId = const Uuid().v5(_trackNamespace, 'settings');

/// A Run's points as column arrays. A column is null when the source had none of it; an element is null for a gap.
/// Stored in `cardio_tracks.points` as base64 of gzipped JSON.
class Track {
  Track({this.time, this.distance, this.lat, this.lon, this.altitude, this.hr, this.cadence, this.laps});

  final List<int?>? time; // seconds from the start
  final List<double?>? distance; // meters from the start
  final List<double?>? lat, lon, altitude;
  final List<int?>? hr;
  final List<double?>? cadence;
  final List<int>? laps; // seconds from the start where Daniel pressed Lap (#69); not a per-point column

  int get length => [time, distance, lat, lon, altitude, hr, cadence].map((c) => c?.length ?? 0).fold(0, (a, b) => a > b ? a : b);

  String encode() {
    final cols = {'t': time, 'd': distance, 'lat': lat, 'lon': lon, 'alt': altitude, 'hr': hr, 'cad': cadence, 'lap': laps};
    return base64.encode(gzip.encode(utf8.encode(jsonEncode({for (final e in cols.entries) if (e.value != null) e.key: e.value}))));
  }

  static Track decode(String points) {
    final j = jsonDecode(utf8.decode(gzip.decode(base64.decode(points)))) as Map<String, dynamic>;
    List<double?>? d(String k) => (j[k] as List?)?.map((v) => (v as num?)?.toDouble()).toList();
    List<int?>? i(String k) => (j[k] as List?)?.map((v) => (v as num?)?.round()).toList();
    return Track(time: i('t'), distance: d('d'), lat: d('lat'), lon: d('lon'), altitude: d('alt'), hr: i('hr'), cadence: d('cad'), laps: (j['lap'] as List?)?.map((v) => (v as num).round()).toList());
  }
}

/// Great-circle distance in meters between two positions.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lon2 - lon1) / 2), 2);
  return 2 * 6371000 * asin(sqrt(a.toDouble()));
}

/// Faster than this (m/s) between two points is a GPS or distance jump, not running.
const maxRunSpeed = 10.0;

/// [t] with a usable distance column for analysis. A healthy column is kept: it matches the Run's distance, while GPS points can be
/// noisy or stray hundreds of km. A broken one (more than half the total in a single step, as exports that repeat the Run's total on
/// every point do) is replaced by the distance along the positions, skipping jumps faster than [maxRunSpeed] and scaled to the column's
/// total. Points before the first position get null, points without one keep the distance so far.
Track withGpsDistance(Track t) {
  final col = t.distance, lat = t.lat, lon = t.lon, time = t.time;
  final known = col?.whereType<double>().toList() ?? const <double>[];
  final total = known.isEmpty ? 0.0 : known.reduce(max);
  final broken = total > 0 && [for (var k = 1; k < known.length; k++) known[k] - known[k - 1]].any((step) => step > total / 2);
  if (!broken || lat == null || lon == null || time == null) return t;
  final dist = <double?>[];
  int? last;
  var positioned = 0;
  for (var i = 0; i < t.length; i++) {
    final has = i < lat.length && i < lon.length && i < time.length && lat[i] != null && lon[i] != null && time[i] != null;
    if (has) {
      var step = last == null ? 0.0 : haversineM(lat[last]!, lon[last]!, lat[i]!, lon[i]!);
      if (last != null && step > maxRunSpeed * max(1, time[i]! - time[last]!)) step = 0; // a jump
      dist.add(last == null ? 0 : dist[last]! + step);
      last = i;
      positioned++;
    } else {
      dist.add(last == null ? null : dist[last]);
    }
  }
  final gps = last == null ? 0.0 : dist[last]!;
  if (positioned < 2 || gps <= 0) return t;
  final scale = total / gps;
  return Track(time: time, distance: [for (final d in dist) d == null ? null : d * scale], lat: lat, lon: lon, altitude: t.altitude, hr: t.hr, cadence: t.cadence, laps: t.laps);
}

/// [base] with every column it lacks filled from [other], matched by nearest absolute time within [toleranceSec]. A column [base] has is never touched.
/// Times are seconds from each track's own start; [baseOffset] and [otherOffset] are how many seconds after the merged track's start each one starts.
/// The result's times run from the merged start. Returns null when [base] needs nothing filled, so a caller can tell nothing changed.
Track? fillMissingColumns(Track base, int baseOffset, Track other, int otherOffset, {int toleranceSec = 10}) {
  final bt = base.time, ot = other.time;
  if (bt == null || ot == null) return null;
  final wantPos = base.lat == null && other.lat != null && other.lon != null;
  final wantDist = base.distance == null && other.distance != null;
  final wantAlt = base.altitude == null && other.altitude != null;
  final wantHr = base.hr == null && other.hr != null;
  final wantCad = base.cadence == null && other.cadence != null;
  if (!(wantPos || wantDist || wantAlt || wantHr || wantCad)) return null;
  final oIdx = [for (var i = 0; i < ot.length; i++) if (ot[i] != null) i]; // by time, as stored
  List<int?> nearest = [
    for (final t in bt)
      if (t == null || oIdx.isEmpty) null else () {
        final abs = t + baseOffset - otherOffset;
        var lo = 0, hi = oIdx.length - 1;
        while (lo < hi) {
          final mid = (lo + hi) ~/ 2;
          if (ot[oIdx[mid]]! < abs) { lo = mid + 1; } else { hi = mid; }
        }
        var best = oIdx[lo];
        if (lo > 0 && (ot[oIdx[lo - 1]]! - abs).abs() <= (ot[best]! - abs).abs()) best = oIdx[lo - 1];
        return (ot[best]! - abs).abs() <= toleranceSec ? best : null;
      }(),
  ];
  List<T?>? take<T>(List<T?>? col) {
    final out = [for (final i in nearest) col == null || i == null || i >= col.length ? null : col[i]];
    return out.any((v) => v != null) ? out : null;
  }

  return Track(
    time: [for (final t in bt) t == null ? null : t + baseOffset],
    distance: wantDist ? take(other.distance) : base.distance,
    lat: wantPos ? take(other.lat) : base.lat,
    lon: wantPos ? take(other.lon) : base.lon,
    altitude: wantAlt ? take(other.altitude) : base.altitude,
    hr: wantHr ? take(other.hr) : base.hr,
    cadence: wantCad ? take(other.cadence) : base.cadence,
    laps: base.laps?.map((l) => l + baseOffset).toList(),
  );
}

/// [t] with its times moved [seconds] later.
Track shiftedBy(Track t, int seconds) => seconds == 0
    ? t
    : Track(time: t.time?.map((v) => v == null ? null : v + seconds).toList(), distance: t.distance, lat: t.lat, lon: t.lon, altitude: t.altitude, hr: t.hr, cadence: t.cadence, laps: t.laps?.map((l) => l + seconds).toList());
