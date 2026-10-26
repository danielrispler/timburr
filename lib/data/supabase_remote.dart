import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync.dart';

/// [Remote] over PostgREST. RLS limits every read and write to the signed-in user.
/// With [userId] (service_role client, tool/timburr-import only) RLS is off, so rows are stamped and filtered by it.
class SupabaseRemote implements Remote {
  SupabaseRemote(this._client, {this.userId});

  final SupabaseClient _client;
  final String? userId;

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) => _client
      .from(table)
      // A bulk upsert needs the same keys on every row, so fill user_id on rows never pushed before.
      .upsert([for (final r in rows) {...r, 'user_id': r['user_id'] ?? userId ?? _client.auth.currentUser!.id}]);

  @override
  Future<List<Map<String, Object?>>> changedSince(String table, DateTime? since, String? afterId, int limit) {
    var q = _client.from(table).select();
    if (userId != null) q = q.eq('user_id', userId!);
    final s = since?.toUtc().toIso8601String();
    if (s != null && afterId == null) q = q.gte('server_updated_at', s);
    if (s != null && afterId != null) q = q.or('server_updated_at.gt.$s,and(server_updated_at.eq.$s,id.gt.$afterId)');
    return q.order('server_updated_at', ascending: true).order('id', ascending: true).limit(limit);
  }
}
