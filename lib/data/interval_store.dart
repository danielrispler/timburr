import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'cardio.dart';
import 'db.dart';
import 'intervals.dart';
import 'track.dart';

/// A saved Interval plan with its row id.
class SavedPlan {
  const SavedPlan(this.id, this.plan);
  final String id;
  final IntervalPlan plan;
}

/// One Interval run in a plan's history, with its steps as run.
class HistoryEntry {
  const HistoryEntry(this.run, this.steps);
  final CardioData run;
  final List<StepMark> steps;

  RepSummary? get summary => summarizeReps(steps);
}

/// The copy of the plan an Interval run was run to; null for a free one and any other Run.
IntervalPlan? planOf(CardioData c) => c.intervalPlan == null ? null : IntervalPlan.fromJson((jsonDecode(c.intervalPlan!) as Map).cast());

/// Interval plans: synced rows (`interval_plans`) that Interval runs point at through `cardio.interval_plan_id`.
class IntervalStore {
  IntervalStore(this._db, this._cardio, {this.onSaved});
  final AppDb _db;
  final CardioStore _cardio;

  /// Called after each save; main wires it to sync.
  final Future<void> Function()? onSaved;

  /// Live plans by name.
  Stream<List<SavedPlan>> watchPlans() => (_db.select(_db.intervalPlans)..where((p) => p.deletedAt.isNull())).watch().map((rows) => [
        for (final r in rows) SavedPlan(r.id, IntervalPlan.fromJson({...(jsonDecode(r.structure) as Map).cast<String, Object?>(), 'name': r.name})),
      ]..sort((a, b) => a.plan.name.toLowerCase().compareTo(b.plan.name.toLowerCase())));

  Future<String> add(IntervalPlan plan) async {
    final id = const Uuid().v4();
    await _write(id, plan);
    return id;
  }

  Future<void> update(String id, IntervalPlan plan) => _write(id, plan);

  Future<void> _write(String id, IntervalPlan plan) async {
    final name = plan.name.trim();
    if (name.isEmpty) throw ArgumentError.value(plan.name, 'name', 'must not be empty');
    await _db.save(_db.intervalPlans, {'id': id, 'name': name, 'structure': jsonEncode(plan.named(name).toJson())});
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }

  /// Soft-deletes the plan. Its Runs keep their reps and their copy of it.
  Future<void> delete(String id) async {
    final p = await (_db.select(_db.intervalPlans)..where((p) => p.id.equals(id))).getSingle();
    await _db.save(_db.intervalPlans, {'id': id, 'name': p.name, 'structure': p.structure, 'deleted_at': DateTime.now()});
    unawaited(onSaved?.call());
  }

  /// The plan of the latest Interval run, for the setup screen to pick; null (Free) when that run was free, its plan is deleted, or there is none.
  Future<String?> lastUsed() async {
    final last = await (_db.select(_db.cardio)
          ..where((c) => c.type.equals('interval') & c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    final id = last?.intervalPlanId;
    if (id == null) return null;
    final plan = await (_db.select(_db.intervalPlans)..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingleOrNull();
    return plan?.id;
  }

  /// The live Interval runs done with [planId], newest first, with their steps.
  Stream<List<HistoryEntry>> watchHistory(String planId) => (_db.select(_db.cardio)
        ..where((c) => c.intervalPlanId.equals(planId) & c.type.equals('interval') & c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.desc(c.startedAt)]))
      .watch()
      .asyncMap((runs) async => [
            for (final r in runs) HistoryEntry(r, (await _db.liveTrackRow(r.id).getSingleOrNull()).let((t) => t == null ? const <StepMark>[] : Track.decode(t.points).steps ?? const [])),
          ]);

  /// Each Step's Last time in plan [planId], by Step id (see [lastTimes]).
  Future<Map<String, LastTime>> lastTimesOf(String planId) async => lastTimes([
        for (final e in await watchHistory(planId).first)
          if (planOf(e.run) case final copy?) (copy, e.steps),
      ]);

  /// Makes a plan named [name] of the steps Run [runId] ran (see [planFromSteps]) and puts the Run in its history. Returns the plan's id.
  Future<String> saveAsPlan(String runId, String name) async {
    final steps = (await _cardio.watchTrack(runId).first)?.steps ?? const [];
    final plan = planFromSteps(steps, name: name.trim());
    final id = await add(plan);
    await _cardio.edit(runId, {'interval_plan_id': id, 'interval_plan': jsonEncode(plan.toJson())});
    return id;
  }
}

extension on CardioTrack? {
  T let<T>(T Function(CardioTrack?) f) => f(this);
}
