import 'track.dart';

/// Max HR used for zones until Daniel sets one or gives his birth year.
const defaultMaxHr = 190;

/// Server-side CHECK range of `settings.max_hr`.
const minMaxHr = 100, maxMaxHr = 250;

/// The Max HR in force: the set value, else 220 minus age from the birth year, else [defaultMaxHr].
int effectiveMaxHr(int? maxHr, int? birthYear, DateTime now) => maxHr ?? (birthYear == null ? defaultMaxHr : maxHrFromBirthYear(birthYear, now));

/// 220 minus age (this year minus [birthYear]), kept inside the allowed range.
int maxHrFromBirthYear(int birthYear, DateTime now) => (220 - (now.year - birthYear)).clamp(minMaxHr, maxMaxHr);

/// Seconds in each of five equal HR bands from 50% to 100% of [maxHr], from the track's HR samples; null without HR and time.
/// Each sample counts for the time until the next one, at most [maxGapSec] (a pause is not time in a zone). Below 50% counts in zone 1, above 100% in zone 5.
List<double>? zoneSeconds(Track t, int maxHr, {int maxGapSec = 30}) {
  final hr = t.hr, time = t.time;
  if (hr == null || time == null) return null;
  final secs = List<double>.filled(5, 0);
  var any = false;
  for (var i = 0; i < hr.length - 1 && i < time.length - 1; i++) {
    final v = hr[i], a = time[i], b = time[i + 1];
    if (v == null || a == null || b == null || b <= a) continue;
    any = true;
    final zone = ((10 * v - 5 * maxHr) ~/ maxHr).clamp(0, 4);
    secs[zone] += (b - a).clamp(0, maxGapSec);
  }
  return any ? secs : null;
}

/// Share of the total in each zone as whole percents; null when there is no time at all.
List<int>? zonePercents(List<double>? secs) {
  final total = secs?.fold<double>(0, (a, b) => a + b) ?? 0;
  return total <= 0 ? null : [for (final s in secs!) (s / total * 100).round()];
}
