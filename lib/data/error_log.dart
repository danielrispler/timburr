import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'sync.dart';

/// The app's [ErrorLog], set in main. Null in tests and before startup.
ErrorLog? errorLog;

/// Records [error] from anywhere in the app. Never throws.
void reportError(String source, Object error, [StackTrace? stack, Map<String, Object?> context = const {}]) =>
    errorLog?.record(source, error, stack, context);

/// Caught errors, kept in drift until pushed to Supabase `app_errors` (supabase/migrations/004_app_errors.sql).
/// An error identical to one not yet pushed (same source, message and stack) bumps its count instead of adding a row.
class ErrorLog {
  ErrorLog(this._db, {this.appVersion, String? os}) : os = os ?? _os();

  final AppDb _db;
  final String? appVersion, os;

  /// Rows kept locally; past this, new distinct errors are dropped so a loop cannot fill the disk.
  static const maxRows = 200;
  static const maxMessage = 2000, maxStack = 8000;

  static String? _cut(String? s, int max) => s == null || s.length <= max ? s : s.substring(0, max);

  static String _os() => '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, ${Platform.localeName}';

  Future<void> record(String source, Object error, [StackTrace? stack, Map<String, Object?> context = const {}]) async {
    final message = _cut('$error', maxMessage)!, st = _cut(stack?.toString(), maxStack);
    if (kDebugMode) debugPrint('[$source] $message\n${st ?? ''}');
    try {
      final now = DateTime.now();
      final same = await (_db.select(_db.errorLogs)
            ..where((e) => e.source.equals(source) & e.message.equals(message) & (st == null ? e.stack.isNull() : e.stack.equals(st)))
            ..limit(1))
          .getSingleOrNull();
      if (same != null) {
        await (_db.update(_db.errorLogs)..where((e) => e.id.equals(same.id)))
            .write(ErrorLogsCompanion(occurrences: Value(same.occurrences + 1), lastAt: Value(now)));
        return;
      }
      if (await _db.errorLogs.count().getSingle() >= maxRows) return;
      await _db.into(_db.errorLogs).insert(ErrorLogsCompanion.insert(
            id: const Uuid().v4(),
            source: source,
            errorType: '${error.runtimeType}',
            message: message,
            stack: Value(st),
            context: Value(jsonEncode(context, toEncodable: (o) => '$o')),
            firstAt: now,
            lastAt: now,
            appVersion: Value(appVersion),
            os: Value(os),
          ));
    } catch (e) {
      debugPrint('ErrorLog.record failed: $e'); // logging must never crash the app
    }
  }

  /// Upserts every local row to `app_errors`, then deletes those not bumped meanwhile. Throws on network errors; rows stay.
  Future<void> push(Remote remote) async {
    final rows = await _db.select(_db.errorLogs).get();
    if (rows.isEmpty) return;
    await remote.upsert('app_errors', [
      for (final r in rows)
        {
          'id': r.id,
          'source': r.source,
          'error_type': r.errorType,
          'message': r.message,
          'stack': r.stack,
          'context': jsonDecode(r.context),
          'count': r.occurrences,
          'first_at': r.firstAt.toUtc().toIso8601String(),
          'last_at': r.lastAt.toUtc().toIso8601String(),
          'app_version': r.appVersion,
          'os': r.os,
        },
    ]);
    for (final r in rows) {
      // A row bumped mid-push keeps its new count and goes up again next time, same id.
      await (_db.delete(_db.errorLogs)..where((e) => e.id.equals(r.id) & e.occurrences.equals(r.occurrences))).go();
    }
  }
}
