// ignore_for_file: avoid_print
// Imports a v1 JSON file (see lib/data/importer.dart importFormat) straight into Supabase, as Daniel.
// Uses the service_role key (bypasses RLS), so every row is stamped and filtered with TIMBURR_USER_ID.
// Run through tool/timburr-import, not directly: it runs under `flutter test` because the data layer imports Flutter.
//
// Flow: pull everything into an in-memory store, run the app's Importer on it, push.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/importer.dart';
import 'package:timburr/data/supabase_remote.dart';
import 'package:timburr/data/sync.dart';

const _file = String.fromEnvironment('FILE');
const _dryRun = bool.fromEnvironment('DRY_RUN');
const _saveRoutines = bool.fromEnvironment('SAVE_ROUTINES');

/// KEY=value lines of .env; comments and blanks skipped.
Map<String, String> _env() => {
      for (final l in File('.env').readAsLinesSync())
        if (l.contains('=') && !l.trimLeft().startsWith('#'))
          l.substring(0, l.indexOf('=')).trim(): l.substring(l.indexOf('=') + 1).trim(),
    };

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  test('import $_file', () async {
    final env = _env();
    for (final k in ['VITE_SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'TIMBURR_USER_ID']) {
      if ((env[k] ?? '').isEmpty) fail('.env is missing $k');
    }
    final data = jsonDecode(File(_file).readAsStringSync());
    final errors = validateImport(data);
    if (errors.isNotEmpty) fail('Invalid file:\n${errors.join('\n')}');

    final client = SupabaseClient(env['VITE_SUPABASE_URL']!, env['SUPABASE_SERVICE_ROLE_KEY']!);
    final db = AppDb(NativeDatabase.memory());
    try {
      final engine = SyncEngine(db, SupabaseRemote(client, userId: env['TIMBURR_USER_ID']));
      Future<void> sync() async {
        await engine.sync();
        if (engine.error.value case final e?) fail('Sync failed: $e');
      }

      await sync(); // empty store: this only pulls
      final importer = Importer(db, Catalog(db, () => File('assets/exercises.json').readAsString()));
      final unknown = await importer.unknownNames(data as Map);
      print('New custom exercises: ${unknown.isEmpty ? 'none' : unknown.join(', ')}');
      if (_dryRun) return print('Dry run: valid, nothing written.');
      await importer.save(data, saveRoutines: _saveRoutines);
      await sync();
      if (await engine.pending() > 0) fail('${await engine.pending()} rows were not pushed');
      print('Imported ${(data['workouts'] as List? ?? []).length} workouts and ${(data['cardio'] as List? ?? []).length} cardio sessions.');
    } finally {
      await db.close();
      await client.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
