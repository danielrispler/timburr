import 'dart:async';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'running.dart';

/// Shoes: synced rows that Runs point at through `cardio.shoe_id`.
class ShoeStore {
  ShoeStore(this._db, {this.onSaved});
  final AppDb _db;

  /// Called after each save; main wires it to sync.
  final Future<void> Function()? onSaved;

  /// Live shoes: in use first, then retired, each by name.
  Stream<List<Shoe>> watchAll() => (_db.select(_db.shoes)..where((s) => s.deletedAt.isNull())).watch().map((rows) => rows..sort(_inUseFirst));

  static int _inUseFirst(Shoe a, Shoe b) {
    final byRetired = (a.retiredAt == null ? 0 : 1) - (b.retiredAt == null ? 0 : 1);
    return byRetired != 0 ? byRetired : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// The pair new Runs get, null when none is set or it is retired.
  Future<String?> defaultId() async =>
      (await (_db.select(_db.shoes)..where((s) => s.deletedAt.isNull() & s.isDefault.equals(true) & s.retiredAt.isNull())).get()).firstOrNull?.id;

  Future<String> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    final id = const Uuid().v4();
    await _db.save(_db.shoes, {'id': id, 'name': trimmed});
    unawaited(onSaved?.call()); // sync in the background; the local write is done
    return id;
  }

  /// Makes [id] the pair new Runs get, and no other.
  Future<void> setDefault(String id) async {
    await _db.transaction(() async {
      for (final s in await (_db.select(_db.shoes)..where((s) => s.deletedAt.isNull() & s.isDefault.equals(true))).get()) {
        if (s.id != id) await _db.save(_db.shoes, {'id': s.id, 'name': s.name, 'is_default': false});
      }
      final s = await (_db.select(_db.shoes)..where((s) => s.id.equals(id))).getSingle();
      await _db.save(_db.shoes, {'id': id, 'name': s.name, 'is_default': true, 'retired_at': null});
    });
    unawaited(onSaved?.call());
  }

  /// Retires [id] (it keeps its Runs and distance, and stops being the default) or brings it back.
  Future<void> setRetired(String id, bool retired) async {
    final s = await (_db.select(_db.shoes)..where((s) => s.id.equals(id))).getSingle();
    await _db.save(_db.shoes, {'id': id, 'name': s.name, 'retired_at': retired ? DateTime.now() : null, if (retired) 'is_default': false});
    unawaited(onSaved?.call());
  }
}

/// Km on each shoe: the sum of the live Runs that name it. A shoe with no Runs is absent.
Map<String, double> shoeTotals(Iterable<CardioData> runs) {
  final km = <String, double>{};
  for (final r in runsOf(runs)) {
    final id = r.shoeId;
    if (id != null) km[id] = (km[id] ?? 0) + (r.distanceKm ?? 0);
  }
  return km;
}
