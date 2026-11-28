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
    await tester.tap(find.byType(PopupMenuButton<String>).last); // the new step's menu
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
    await tester.tap(find.text('No target'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pace').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Pace (m:ss /km)'), '4:05');
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
    await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use last time as targets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect([for (final s in result.single!.allSteps) s.pace], [250, null, null]);
  });
}
