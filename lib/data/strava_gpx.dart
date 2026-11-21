import 'dart:math';

import 'package:xml/xml.dart';

import 'strava_tcx.dart';

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(lat2 - lat1) / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(rad(lon2 - lon1) / 2), 2);
  return 2 * 6371000 * asin(sqrt(a.toDouble()));
}

/// Reads a GPX export into the same [Recording] a TCX of the track gives. GPX has no distance, so it is summed from the positions.
ParsedFile parseStravaGpx(String fileName, String xml) {
  final name = fileName.split('/').last;
  if (!name.toLowerCase().endsWith('.gpx')) return ParsedFile(name, skipReason: 'Not a GPX file');
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return ParsedFile(name, skipReason: 'Not readable as GPX');
  }
  if (doc.findAllElements('trk').isEmpty) return ParsedFile(name, skipReason: 'No track in the file');

  final time = <DateTime>[], dist = <double?>[], lat = <double?>[], lon = <double?>[], alt = <double?>[], hr = <int?>[];
  var total = 0.0;
  double? lastLat, lastLon;
  for (final pt in doc.findAllElements('trkpt')) {
    final t = DateTime.tryParse(pt.getElement('time')?.innerText.trim() ?? '');
    final la = double.tryParse(pt.getAttribute('lat') ?? ''), lo = double.tryParse(pt.getAttribute('lon') ?? '');
    if (t == null || la == null || lo == null) continue;
    if (lastLat != null) total += _haversine(lastLat, lastLon!, la, lo);
    lastLat = la;
    lastLon = lo;
    time.add(t);
    dist.add(total);
    lat.add(la);
    lon.add(lo);
    alt.add(double.tryParse(pt.getElement('ele')?.innerText.trim() ?? ''));
    final v = pt.findAllElements('hr', namespaceUri: '*').firstOrNull?.innerText.trim(); // <gpxtpx:hr> in the Garmin extension
    hr.add(v == null ? null : double.tryParse(v)?.round());
  }
  if (time.isEmpty) return ParsedFile(name, skipReason: 'No track points');
  if (total <= 0) return ParsedFile(name, skipReason: 'No distance recorded');
  final id = doc.findAllElements('metadata').firstOrNull?.getElement('time')?.innerText.trim();
  return buildRunFile(name, id == null || id.isEmpty ? name : id, time: time, dist: dist, lat: lat, lon: lon, alt: alt, hr: hr, distanceM: total);
}
