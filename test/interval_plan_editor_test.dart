import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/intervals.dart';
import 'package:timburr/ui/running/interval_plans.dart';

void main() {
  /// Opens the editor on [initial] from a page that keeps what it pops in [result].
  Future<List<IntervalPlan?>> open(WidgetTester tester, {IntervalPlan? initial, Map<String, LastTime> lastTimes = const {}}) async {
    tester.view.physicalSize = const Size(1080, 4800); // tall enough to build every step
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final result = <IntervalPlan?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result.add(await Navigator.of(context).push<IntervalPlan>(MaterialPageRoute(builder: (_) => IntervalPlanEditor(initial: initial, lastTimes: lastTimes)))),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('a new plan starts as warm-up, 6 × (400 m / 1:30), cool-down; Add repeat, Add step and Move into repeat build on it', (tester) async {
    final result = await open(tester);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('× 6'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ladder');
    await tester.tap(find.text('Add repeat').last);
    await tester.pump();
    await tester.tap(find.text('Add step').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More').last); // the new step's actions
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move into repeat above'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result.single!.name, 'Ladder');
    expect(result.single!.describe(), 'open warm-up · 6 × (400 m / 1:30) · open cool-down · 2 × (400 m / 1:30 / 400 m)');
  });

  testWidgets('a Step\'s page sets its Target pace, and going back keeps it', (tester) async {
    final plan = IntervalPlan(name: 'One', items: [const PlanStep('r', StepKind.rep, StepTarget.meters(1000))]);
    final result = await open(tester, initial: plan);
    await tester.tap(find.text('1 km'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Pace'), '405'); // the colon comes by itself
    expect(find.text('4:05'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1 km · @ 4:05 /km'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result.single!.allSteps.single.pace, 245);
  });

  testWidgets('Last time shows on a Step that is unchanged since, and Use last time as targets copies it when it can be a Target pace', (tester) async {
    final plan = IntervalPlan(name: 'Two', items: [
      const PlanStep('r', StepKind.rep, StepTarget.meters(1000)),
      const PlanStep('w', StepKind.recovery, StepTarget.time(60)),
      const PlanStep('c', StepKind.cooldown, StepTarget.time(300)),
    ]);
    final result = await open(tester, initial: plan, lastTimes: {
      'w': const LastTime(StepKind.recovery, StepTarget.time(60), 1500), // walked: 25:00 /km is no Target pace
      'r': const LastTime(StepKind.rep, StepTarget.meters(1000), 250.4),
      'c': const LastTime(StepKind.cooldown, StepTarget.time(600), 330), // the cool-down was 10:00 then: no Last time
    });
    expect(find.text('Last time 4:10 /km'), findsOneWidget);
    await tester.tap(find.byTooltip('Use last time as targets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect([for (final s in result.single!.allSteps) s.pace], [250, null, null]);
  });

  testWidgets('swiping a Step left deletes it, and Undo brings it back where it was', (tester) async {
    final plan = IntervalPlan(name: 'Three', items: [
      const PlanStep('w', StepKind.warmup, null),
      const PlanStep('r', StepKind.rep, StepTarget.meters(1000)),
      const PlanStep('c', StepKind.cooldown, null),
    ]);
    final result = await open(tester, initial: plan);
    await tester.drag(find.text('1 km'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 km'), findsNothing);
    expect(find.text('Rep deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect([for (final s in result.single!.allSteps) s.id], ['w', 'r', 'c']);
  });

  group('typing a time or pace', () {
    String type(List<String> keys) {
      var v = TextEditingValue.empty;
      for (final text in keys) {
        v = const ClockInputFormatter().formatEditUpdate(v, TextEditingValue(text: text));
      }
      return v.text;
    }

    test('fills in from the right, the colon put in by itself', () {
      expect(type(['1']), '0:01');
      expect(type(['1', '0:011', '0:113']), '1:13');
      expect(type(['1', '0:010', '0:103', '1:030']), '10:30');
    });

    test('backspace takes the last digit; nothing left is empty; more than four digits are refused', () {
      expect(const ClockInputFormatter().formatEditUpdate(const TextEditingValue(text: '1:30'), const TextEditingValue(text: '1:3')).text, '0:13');
      expect(const ClockInputFormatter().formatEditUpdate(const TextEditingValue(text: '0:01'), const TextEditingValue(text: '0:0')).text, '');
      expect(const ClockInputFormatter().formatEditUpdate(const TextEditingValue(text: '10:30'), const TextEditingValue(text: '10:305')).text, '10:30');
    });
  });
}
