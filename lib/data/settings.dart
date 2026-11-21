import 'dart:async';

import 'db.dart';
import 'hr_zones.dart';
import 'track.dart';

/// The single synced settings row. A deleted row (a "replace" restore of an old backup) reads as unset and is revived on the next save.
class SettingsStore {
  SettingsStore(this._db, {this.onSaved});
  final AppDb _db;

  /// Called after each save; main wires it to sync.
  final Future<void> Function()? onSaved;

  Stream<AppSetting?> watch() => (_db.select(_db.appSettings)..where((s) => s.deletedAt.isNull())).watchSingleOrNull();

  Future<void> setMaxHr(int maxHr) {
    if (maxHr < minMaxHr || maxHr > maxMaxHr) throw ArgumentError.value(maxHr, 'maxHr', 'must be $minMaxHr..$maxMaxHr');
    return _write({'max_hr': maxHr});
  }

  /// Remembers [birthYear] and sets Max HR to 220 minus age.
  Future<void> setBirthYear(int birthYear, {DateTime? now}) => _write({'birth_year': birthYear, 'max_hr': maxHrFromBirthYear(birthYear, now ?? DateTime.now())});

  Future<void> _write(Map<String, Object?> fields) async {
    final existing = await (_db.select(_db.appSettings)..where((s) => s.id.equals(settingsRowId))).getSingleOrNull();
    final revive = existing?.deletedAt != null;
    await _db.save(_db.appSettings, {
      'id': settingsRowId,
      if (revive) ...{'birth_year': null, 'max_hr': null, 'stride_m': null, 'stride_samples': null}, // the deleted row's values are stale
      ...fields,
      'deleted_at': null,
    });
    unawaited(onSaved?.call()); // sync in the background; the local write is done
  }
}
