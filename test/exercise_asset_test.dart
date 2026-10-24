import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Checks the output of scripts/build-exercises.mjs: trimmed fields only, no images.
void main() {
  final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List;

  test('library asset holds the full pinned free-exercise-db list', () {
    expect(list.length, greaterThan(800));
  });

  test('every entry has exactly the trimmed fields, and no images', () {
    const keys = {'id', 'name', 'category', 'equipment', 'primaryMuscles', 'secondaryMuscles', 'instructions'};
    for (final e in list.cast<Map<String, dynamic>>()) {
      expect(e.keys.toSet(), keys, reason: e['id'] as String?);
    }
    expect(list.any((e) => (e as Map).containsKey('images')), isFalse);
  });

  test('a known exercise survives trimming intact', () {
    final squat = list.cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == 'Barbell_Squat');
    expect(squat['category'], 'strength');
    expect(squat['equipment'], 'barbell');
    expect(squat['primaryMuscles'], contains('quadriceps'));
  });
}
