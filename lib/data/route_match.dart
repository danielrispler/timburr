import 'db.dart';
import 'running.dart';
import 'track.dart';

/// Two routes match when their starts are within this many meters,
const matchStartM = 150.0;

/// every point of one is within this many meters of the same share along the other,
const matchPathM = 120.0;

/// and their lengths differ by no more than this share. Run the other way, or a shorter or longer loop, fails one of these.
const matchLengthShare = 0.15;

const _samples = 40;

/// Outdoor Runs over the same route, oldest first.
class RouteGroup {
  const RouteGroup(this.runs);

  final List<CardioData> runs;
}

class _Shape {
  const _Shape(this.points, this.lengthM);

  final List<(double, double)> points;
  final double lengthM;
}

/// [route] as [_samples] points evenly spaced along its length, or null when it has no length to speak of.
_Shape? _shape(String? route) {
  final pts = parseRoute(route);
  if (pts.length < 2) return null;
  final cum = [0.0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + haversineM(pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2));
  }
  final total = cum.last;
  if (total < 100) return null;
  final out = <(double, double)>[];
  var seg = 1;
  for (var k = 0; k < _samples; k++) {
    final at = total * k / (_samples - 1);
    while (seg < pts.length - 1 && cum[seg] < at) {
      seg++;
    }
    final span = cum[seg] - cum[seg - 1];
    final f = span == 0 ? 0.0 : ((at - cum[seg - 1]) / span).clamp(0.0, 1.0);
    out.add((pts[seg - 1].$1 + (pts[seg].$1 - pts[seg - 1].$1) * f, pts[seg - 1].$2 + (pts[seg].$2 - pts[seg - 1].$2) * f));
  }
  return _Shape(out, total);
}

bool _matches(_Shape a, _Shape b) {
  if ((a.lengthM - b.lengthM).abs() > matchLengthShare * a.lengthM) return false;
  for (var i = 0; i < _samples; i++) {
    final d = haversineM(a.points[i].$1, a.points[i].$2, b.points[i].$1, b.points[i].$2);
    if (d > (i == 0 ? matchStartM : matchPathM)) return false;
  }
  return true;
}

/// The groups of at least two outdoor Runs over the same route, computed from their stored `route` (no schema needed).
/// Each Run joins the first group whose first Run it matches. Biggest group first, then the most recently run.
List<RouteGroup> groupRuns(Iterable<CardioData> runs) {
  final sorted = [for (final r in runsOf(runs)) if (r.route != null) r]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final reps = <_Shape>[];
  final members = <List<CardioData>>[];
  for (final r in sorted) {
    final s = _shape(r.route);
    if (s == null) continue;
    final at = reps.indexWhere((rep) => _matches(rep, s));
    if (at < 0) {
      reps.add(s);
      members.add([r]);
    } else {
      members[at].add(r);
    }
  }
  return [for (final m in members) if (m.length >= 2) RouteGroup(m)]
    ..sort((a, b) => a.runs.length != b.runs.length ? b.runs.length.compareTo(a.runs.length) : b.runs.last.startedAt.compareTo(a.runs.last.startedAt));
}

/// The group holding the Run [id], or null when it has none.
RouteGroup? groupOf(Iterable<RouteGroup> groups, String id) {
  for (final g in groups) {
    if (g.runs.any((r) => r.id == id)) return g;
  }
  return null;
}
