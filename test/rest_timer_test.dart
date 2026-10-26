import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/catalog.dart';
import 'package:timburr/data/db.dart';
import 'package:timburr/data/rest_timer.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('offer highlights last rest; starting saves it and replaces the previous alarm', () async {
    final db = AppDb(NativeDatabase.memory());
    final catalog = Catalog(db, () async => '[]');
    final calls = <String>[];
    final timer = RestTimer(catalog,
        schedule: (d) async => calls.add('schedule ${d.inSeconds}'), cancel: () async => calls.add('cancel'));
    final id = await catalog.saveCustom(name: 'Sled', loadType: 'weighted', muscles: [], equipment: 'other');

    await timer.offer(id);
    expect(timer.highlightSec, isNull);
    await timer.start(90);
    await timer.start(120);
    expect(calls, ['cancel', 'schedule 90', 'cancel', 'schedule 120']);
    expect(timer.remaining!.inSeconds, inInclusiveRange(119, 120));

    await timer.offer(id);
    expect(timer.highlightSec, 120);
    timer.dispose();
    await db.close();
  });

  test('countdown starts and last rest is saved even when scheduling throws', () async {
    final db = AppDb(NativeDatabase.memory());
    final catalog = Catalog(db, () async => '[]');
    final timer = RestTimer(catalog, schedule: (_) async => throw Exception('no alarm'), cancel: () async {});
    final id = await catalog.saveCustom(name: 'Sled', loadType: 'weighted', muscles: [], equipment: 'other');

    await timer.offer(id);
    await timer.start(60);
    expect(timer.remaining!.inSeconds, inInclusiveRange(59, 60));
    expect((await catalog.byId(id))!.lastRestSec, 60);
    timer.dispose();
    await db.close();
  });
}
