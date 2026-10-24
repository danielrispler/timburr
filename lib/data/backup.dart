import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'sync.dart';

/// JSON backup of every synced table, independent of Supabase. See docs/design.md, Backup restore.
class Backup {
  Backup(this._db);

  final AppDb _db;

  static const format = 'timburr-backup', version = 1;

  /// All rows of all synced tables, soft-deleted ones included, in the Supabase wire shape.
  Future<String> export() async => jsonEncode({
        'format': format,
        'version': version,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'tables': {
          for (final t in _db.syncedTables)
            t.actualTableName: [
              for (final r in await _db.customSelect('select * from ${t.actualTableName}', readsFrom: {t}).get()) rowToJson(t, r.data),
            ],
        },
      });

  /// Restores [json] in one transaction and marks the written rows dirty, so they sync.
  /// [replace]: the store becomes the backup; rows missing from it are soft-deleted, so it can be undone.
  /// Otherwise merge: upsert by id, the newer `updated_at` wins.
  /// `user_id` and `server_updated_at` stay local, so a backup from another project restores cleanly.
  Future<void> restore(String json, {required bool replace}) async {
    final tables = _parse(json);
    final now = DateTime.now();
    await _db.transaction(() async {
      for (final t in _db.syncedTables) {
        final name = t.actualTableName;
        final rows = tables[name] ?? const [];
        final local = {
          for (final r in await _db.customSelect('select id, updated_at, deleted_at from $name').get())
            r.data['id'] as String: r.data,
        };
        for (final r in rows) {
          final mine = local[r['id']];
          if (!replace && mine != null && !DateTime.parse(r['updated_at'] as String).isAfter(DateTime.parse(mine['updated_at'] as String))) {
            continue;
          }
          final values = {
            ...rowFromJson(t, r)..remove('user_id')..remove('server_updated_at'),
            if (replace) 'updated_at': now,
            'dirty': 1,
          };
          await _db.customInsert(
            'insert into $name (${values.keys.join(', ')}) values (${List.filled(values.length, '?').join(', ')}) '
            'on conflict (id) do update set ${values.keys.map((k) => '$k = excluded.$k').join(', ')}',
            variables: [for (final v in values.values) Variable(v)],
            updates: {t},
          );
        }
        if (!replace) continue;
        final kept = {for (final r in rows) r['id']};
        for (final MapEntry(key: id, value: r) in local.entries) {
          if (kept.contains(id) || r['deleted_at'] != null) continue;
          await _db.customUpdate('update $name set deleted_at = ?, updated_at = ?, dirty = 1 where id = ?',
              variables: [Variable(now), Variable(now), Variable(id)], updates: {t});
        }
      }
    });
  }

  /// Checks the envelope and that each row has an id and updated_at. Foreign keys are checked by SQLite.
  Map<String, List<Map<String, Object?>>> _parse(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Not a JSON file.');
    }
    if (root is! Map || root['format'] != format) throw const FormatException('Not a Timburr backup.');
    if (root['version'] != version) throw FormatException('Unsupported backup version ${root['version']}.');
    final tables = root['tables'];
    if (tables is! Map) throw const FormatException('Backup has no tables.');
    final known = {for (final t in _db.syncedTables) t.actualTableName};
    final out = <String, List<Map<String, Object?>>>{};
    for (final MapEntry(:key, :value) in tables.entries) {
      if (!known.contains(key)) throw FormatException('Unknown table $key.');
      if (value is! List) throw FormatException('$key is not a list.');
      out[key as String] = [
        for (final r in value)
          if (r is Map && r['id'] is String && r['updated_at'] is String && DateTime.tryParse(r['updated_at'] as String) != null)
            r.cast<String, Object?>()
          else
            throw FormatException('$key: a row without a valid id or updated_at.'),
      ];
    }
    return out;
  }
}

/// The Home reminder shows when the last export (or dismissal) is more than 14 days old, or there is none.
bool backupDue({DateTime? lastExport, DateTime? dismissedAt, required DateTime now}) {
  final last = [lastExport, dismissedAt].whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  return last == null || now.difference(last) > const Duration(days: 14);
}

/// Last export and dismissal times, kept in a small local file (not synced).
class BackupReminder {
  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/backup_reminder.json');

  static Future<Map<String, dynamic>> _read() async {
    try {
      return jsonDecode(await (await _file()).readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _mark(String key) async {
    final data = {...await _read(), key: DateTime.now().toUtc().toIso8601String()};
    await (await _file()).writeAsString(jsonEncode(data));
  }

  static Future<void> markExported() => _mark('last_export');
  static Future<void> markDismissed() => _mark('dismissed_at');

  static Future<bool> due() async {
    final d = await _read();
    DateTime? at(String k) => d[k] is String ? DateTime.tryParse(d[k] as String) : null;
    return backupDue(lastExport: at('last_export'), dismissedAt: at('dismissed_at'), now: DateTime.now());
  }
}
