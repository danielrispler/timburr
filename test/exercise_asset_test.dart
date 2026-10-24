import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Checks the output of scripts/build-exercises.mjs: trimmed fields only, media as a file stem.
void main() {
  final list = (jsonDecode(File('assets/exercises.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  test('library asset holds the full pinned exercises-dataset list, each with media', () {
    expect(list.length, greaterThan(1300));
    expect(list.where((e) => e['media'] == null), isEmpty);
  });

  test('every entry has exactly the trimmed fields', () {
    const keys = {
      'id', 'name', 'category', 'equipment', 'primaryMuscles', 'secondaryMuscles', 'instructions', 'aliases',
      'legacyIds', 'media',
    };
    for (final e in list) {
      expect(e.keys.toSet(), keys, reason: e['id'] as String?);
    }
  });

  test('every exercise logged before the switch maps to exactly one new entry', () {
    const logged = [
      'Barbell_Deadlift', 'Dumbbell_Rear_Lunge', 'Seated_Leg_Curl', 'Leg_Extensions', 'Standing_Dumbbell_Calf_Raise',
      'Pullups', 'Standing_Military_Press', 'Barbell_Incline_Bench_Press_-_Medium_Grip',
      'Seated_One-arm_Cable_Pulley_Rows', 'Cable_Crossover', 'Hammer_Curls', 'Reverse_Flyes',
      'Standing_Dumbbell_Triceps_Extension', 'Barbell_Squat', 'Romanian_Deadlift', 'Calf_Press', 'Thigh_Abductor',
      'Barbell_Bench_Press_-_Medium_Grip', 'Bent_Over_Barbell_Row', 'Wide-Grip_Lat_Pulldown', 'Dumbbell_Bicep_Curl',
      'Triceps_Pushdown_-_Rope_Attachment',
    ];
    final legacy = [for (final e in list) ...(e['legacyIds'] as List).cast<String>()];
    expect(legacy.toSet().length, legacy.length);
    expect(legacy, containsAll(logged));
  });

  test('a known exercise survives trimming intact, findable by its old name', () {
    final squat = list.firstWhere((e) => e['id'] == '0043');
    expect(squat['name'], 'Barbell Full Squat');
    expect(squat['equipment'], 'barbell');
    expect(squat['legacyIds'], containsAll(['Barbell_Squat', 'Barbell_Full_Squat']));
    expect(squat['aliases'], contains('Barbell Squat'));
    expect(squat['media'], '0043-qXTaZnJ');
  });
}
