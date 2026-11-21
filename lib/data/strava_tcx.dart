import 'package:xml/xml.dart';

import 'run_file.dart';

/// Reads a Strava TCX export into a [Recording] (source `file`). Lap totals include pauses, so Moving time comes from the file name.
ParsedFile parseStravaTcx(String fileName, String xml) {
  final name = fileName.split('/').last;
  if (!name.toLowerCase().endsWith('.tcx')) return ParsedFile(name, skipReason: 'Not a TCX file');
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return ParsedFile(name, skipReason: 'Not readable as TCX');
  }
  final activity = doc.findAllElements('Activity').firstOrNull;
  if (activity == null) return ParsedFile(name, skipReason: 'No activity in the file');

  String? text(XmlElement e, String tag) => e.getElement(tag)?.innerText.trim();

  // Strava restarts the trackpoint distance in every lap; the track runs on from the previous lap's end.
  final time = <DateTime>[], dist = <double?>[], lat = <double?>[], lon = <double?>[], alt = <double?>[], hr = <int?>[];
  var offset = 0.0;
  for (final lap in activity.findElements('Lap')) {
    var lapEnd = 0.0;
    for (final tp in lap.findAllElements('Trackpoint')) {
      final t = DateTime.tryParse(text(tp, 'Time') ?? '');
      if (t == null) continue;
      final d = double.tryParse(text(tp, 'DistanceMeters') ?? '');
      final pos = tp.getElement('Position');
      time.add(t);
      dist.add(d == null ? null : offset + d);
      lat.add(pos == null ? null : double.tryParse(text(pos, 'LatitudeDegrees') ?? ''));
      lon.add(pos == null ? null : double.tryParse(text(pos, 'LongitudeDegrees') ?? ''));
      alt.add(double.tryParse(text(tp, 'AltitudeMeters') ?? ''));
      final v = tp.getElement('HeartRateBpm')?.getElement('Value')?.innerText.trim();
      hr.add(v == null ? null : double.tryParse(v)?.round());
      if (d != null && d > lapEnd) lapEnd = d;
    }
    offset += double.tryParse(text(lap, 'DistanceMeters') ?? '') ?? lapEnd;
  }
  return buildRunFile(name, text(activity, 'Id') ?? name, time: time, dist: dist, lat: lat, lon: lon, alt: alt, hr: hr, distanceM: offset);
}
