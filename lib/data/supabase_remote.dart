import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync.dart';

/// [Remote] over PostgREST. RLS limits every read and write to the signed-in user.
class SupabaseRemote implements Remote {
  SupabaseRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) => _client
      .from(table)
      // A bulk upsert needs the same keys on every row, so fill user_id on rows never pushed before.
      .upsert([for (final r in rows) {...r, 'user_id': r['user_id'] ?? _client.auth.currentUser!.id}]);

  @override
  Future<List<Map<String, Object?>>> changedSince(String table, DateTime? since, int offset, int limit) {
    var q = _client.from(table).select();
    if (since != null) q = q.gte('server_updated_at', since.toUtc().toIso8601String());
    return q.order('server_updated_at', ascending: true).order('id', ascending: true).range(offset, offset + limit - 1);
  }
}
