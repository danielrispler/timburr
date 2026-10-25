import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/data/health.dart';

// OCR lines of the Google Health "Upper A" screenshot: labels left, values right, values a little off-centre.
OcrLine l(String text, double left, double top, double h) => (text: text, left: left, top: top, bottom: top + h);

void main() {
  test('reads the Google Health workout summary row by row', () {
    final lines = [
      l('Upper A', 62, 305, 70),
      l('Today • 20:15 • Fitbit Air', 145, 415, 45),
      l('5 • Moderate', 445, 550, 70),
      l('Overall effort', 62, 565, 40),
      l('Duration', 62, 720, 40),
      l('1h 1m 29s', 555, 705, 70),
      l('255 cal', 630, 860, 70),
      l('Energy burned', 62, 905, 40),
      l('12% of your goal', 588, 958, 40),
      l('Heart rate (avg)', 62, 1090, 40),
      l('91 bpm', 622, 1075, 70),
      l('Cardio load', 62, 1243, 40),
      l('5', 820, 1228, 70),
    ];
    expect(parseHealth(lines), (avgHr: 91, calories: 255, activeSec: 3689, effort: 5, cardioLoad: 5));
  });

  test('missing fields stay null; minutes-only duration and 1,234 cal parse', () {
    expect(parseHealth([l('Duration', 0, 0, 40), l('45m 3s', 500, 0, 40), l('1,234 cal', 500, 100, 40)]),
        (avgHr: null, calories: 1234, activeSec: 2703, effort: null, cardioLoad: null));
  });
}
