import 'package:xml/xml.dart';

import 'run_file.dart';
import 'track.dart';

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
    if (lastLat != null) total += haversineM(lastLat, lastLon!, la, lo);
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
  final id = doc.findAllElements('metadata').firstOrNull?.getElement('time')?.innerText.trim();
  return buildRunFile(name, id == null || id.isEmpty ? name : id, time: time, dist: dist, lat: lat, lon: lon, alt: alt, hr: hr, distanceM: total);
}
