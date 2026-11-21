import 'cardio.dart';
import 'db.dart';

/// The pace (seconds per km) a treadmill estimate uses until Daniel has corrected a few treadmill distances: 6:00 per km.
const defaultTreadmillPaceSecPerKm = 360.0;

/// How many of his latest corrected treadmill Runs the usual pace is the median of.
const treadmillPaceSamples = 10;

/// Daniel's usual treadmill pace in seconds per km: the median pace of his latest [treadmillPaceSamples] treadmill Runs whose distance he edited
/// (`edited_fields` has `distance_km`: he typed what the treadmill showed). [runs] may be any Runs in any order; deleted Runs and ones without a
/// distance or time are skipped. [defaultTreadmillPaceSecPerKm] when none qualify.
double usualTreadmillPace(Iterable<CardioData> runs) {
  final corrected = [
    for (final r in runs)
      if (r.type == 'treadmill' && r.deletedAt == null && r.editedFields.contains('distance_km') && (r.distanceKm ?? 0) > 0 && r.durationSec > 0) r,
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final paces = [for (final r in corrected.take(treadmillPaceSamples)) r.durationSec / r.distanceKm!]..sort();
  if (paces.isEmpty) return defaultTreadmillPaceSecPerKm;
  final mid = paces.length ~/ 2;
  return paces.length.isOdd ? paces[mid] : (paces[mid - 1] + paces[mid]) / 2;
}

/// What the Treadmill data form saves, by SQL column name. [initial] is what the fields showed (the best estimates) and [typed] what they show now,
/// both keyed `distance_km`, `duration_sec` (m:ss), `incline_pct`, `steps`, `calories`. A field whose text did not change, or is blank, or does
/// not parse, is left out: an estimate Daniel did not touch stays an estimate, so a later Fitbit merge may still improve it. The rest go to
/// [CardioStore.edit] and become edited fields.
Map<String, Object?> treadmillEdits(Map<String, String> initial, Map<String, String> typed) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in typed.entries) {
    final text = value.trim();
    if (text.isEmpty || text == (initial[key] ?? '').trim()) continue;
    if (key == 'duration_sec') {
      final s = parseDuration(text);
      if (s != null && s > 0) out[key] = s;
      continue;
    }
    final n = parseNum(text);
    if (n == null) continue;
    switch (key) {
      case 'distance_km':
        out[key] = roundTo(n, 3);
      case 'incline_pct':
        out[key] = roundTo(n, 1);
      case 'steps' || 'calories':
        out[key] = n.round();
    }
  }
  return out;
}
