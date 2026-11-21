import 'dart:async';

import 'db.dart';
import 'running.dart';
import 'stats.dart';
import 'track.dart';

/// The single synced goals row. A deleted row (a "replace" restore of an old backup) reads as unset and is revived on the next save.
class GoalStore {
  GoalStore(this._db, {this.onSaved});
  final AppDb _db;

  /// Called after each save; main wires it to sync.
  final Future<void> Function()? onSaved;

  Stream<Goal?> watch() => (_db.select(_db.goals)..where((g) => g.deletedAt.isNull())).watchSingleOrNull();

  /// Saves both goals in km; null clears one. A goal must be above zero.
  Future<void> set({double? weeklyKm, double? yearlyKm}) async {
    for (final km in [weeklyKm, yearlyKm]) {
      if (km != null && !(km > 0)) throw ArgumentError.value(km, 'goal', 'must be above 0');
    }
    await _db.save(_db.goals, {'id': goalsRowId, 'weekly_km': weeklyKm, 'yearly_km': yearlyKm, 'deleted_at': null});
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }
}

/// How far a distance goal has come.
typedef GoalProgress = ({double doneKm, double goalKm, double fraction, double remainingKm});

GoalProgress _progress(double done, double goal) => (doneKm: done, goalKm: goal, fraction: done / goal, remainingKm: done >= goal ? 0.0 : goal - done);

/// Progress of the weekly goal: Runs from this week's Monday until [now].
GoalProgress weeklyProgress(Iterable<CardioData> runs, double goalKm, DateTime now) =>
    _progress(totalsBetween(runs, mondayOf(now), now).km, goalKm);

/// Progress of the yearly goal: Runs from 1 January until [now].
GoalProgress yearlyProgress(Iterable<CardioData> runs, double goalKm, DateTime now) =>
    _progress(totalsBetween(runs, DateTime(now.year), now).km, goalKm);

/// Km a week still needed to reach the yearly goal: what is left divided by the weeks left in the year (fractional, so it moves smoothly). 0 once reached.
double weeklyPaceNeeded(GoalProgress yearly, DateTime now) {
  if (yearly.remainingKm == 0) return 0;
  final weeksLeft = DateTime(now.year + 1).difference(now).inMinutes / (7 * 24 * 60);
  return yearly.remainingKm / weeksLeft;
}
