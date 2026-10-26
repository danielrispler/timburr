import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/error_log.dart';
import 'package:timburr/data/sync.dart';

/// Keeps every upsert to app_errors; [fail] makes the next upsert throw.
class ErrorsRemote implements Remote {
  final pushed = <List<Map<String, Object?>>>[];
  bool fail = false;
  bool failPull = false; // breaks sync but leaves the app_errors upsert working

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) async {
    if (fail) throw Exception('offline');
    if (table == 'app_errors') pushed.add(rows);
  }

  @override
  Future<List<Map<String, Object?>>> changedSince(String table, DateTime? since, String? afterId, int limit) async {
    if (fail || failPull) throw Exception('offline');
    return [];
  }
}

void main() {
  late AppDb db;
  late ErrorLog log;
  late ErrorsRemote remote;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    log = ErrorLog(db, appVersion: '0.1.0+1', os: 'android 15');
    remote = ErrorsRemote();
  });
  tearDown(() => db.close());

  test('the same error twice is pushed once, with count 2 and its details', () async {
    final stack = StackTrace.current;
    await log.record('sync', StateError('boom'), stack, {'table': 'sets'});
    await log.record('sync', StateError('boom'), stack, {'table': 'sets'});
    await log.push(remote);

    expect(remote.pushed, hasLength(1));
    final row = remote.pushed.single.single;
    expect(row, containsPair('source', 'sync'));
    expect(row, containsPair('error_type', 'StateError'));
    expect(row, containsPair('message', 'Bad state: boom'));
    expect(row, containsPair('count', 2));
    expect(row, containsPair('context', {'table': 'sets'}));
    expect(row, containsPair('app_version', '0.1.0+1'));
    expect(row, containsPair('os', 'android 15'));
    expect(row['stack'], contains('error_log_test.dart'));
  });

  test('a huge message and stack are cut to their caps', () async {
    await log.record('import', Exception('x' * 50000), StackTrace.fromString('y' * 50000));
    await log.push(remote);

    final row = remote.pushed.single.single;
    expect((row['message'] as String).length, 2000);
    expect((row['stack'] as String).length, 8000);
  });

  test('keeps at most 200 distinct errors while offline, still counting known ones', () async {
    for (var i = 0; i < 205; i++) {
      await log.record('flutter', Exception('e$i'));
    }
    await log.record('flutter', Exception('e0'));
    await log.push(remote);

    final rows = remote.pushed.single;
    expect(rows, hasLength(200));
    expect(rows.firstWhere((r) => r['message'] == 'Exception: e0')['count'], 2);
  });

  test('a failed sync is recorded, and the next good sync pushes it', () async {
    final engine = SyncEngine(db, remote, errors: log);
    remote.fail = true;
    await engine.sync();
    expect(engine.error.value, contains('offline'));
    expect(remote.pushed, isEmpty);

    remote.fail = false;
    await engine.sync();
    final row = remote.pushed.single.single;
    expect((row['source'], row['message']), ('sync', 'Exception: offline'));
    expect(row['stack'], isNotNull);
  });

  test('a sync that keeps failing still pushes its own error', () async {
    remote.failPull = true;
    await SyncEngine(db, remote, errors: log).sync();
    expect(remote.pushed.single.single['source'], 'sync');
  });

  test('a failed push keeps the errors for the next one', () async {
    await log.record('backup', Exception('disk full'));
    remote.fail = true;
    await expectLater(log.push(remote), throwsException);

    remote.fail = false;
    await log.push(remote);
    await log.push(remote);
    expect(remote.pushed, hasLength(1)); // sent once, then gone locally
  });
}
