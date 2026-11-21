import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

const _trackNamespace = '7a1e5d52-3b0c-5f1a-8c2e-9d4b6a7c8e01';

/// Deterministic `cardio_tracks` id of a Run, so two offline devices agree (one track per Run).
String trackRowId(String cardioId) => const Uuid().v5(_trackNamespace, cardioId);

/// Id of the one `settings` row. Fixed, so every device and a restore into a fresh project agree.
final settingsRowId = const Uuid().v5(_trackNamespace, 'settings');

/// A Run's points as column arrays. A column is null when the source had none of it; an element is null for a gap.
/// Stored in `cardio_tracks.points` as base64 of gzipped JSON.
class Track {
  Track({this.time, this.distance, this.lat, this.lon, this.altitude, this.hr, this.cadence});

  final List<int?>? time; // seconds from the start
  final List<double?>? distance; // meters from the start
  final List<double?>? lat, lon, altitude;
  final List<int?>? hr;
  final List<double?>? cadence;

  int get length => [time, distance, lat, lon, altitude, hr, cadence].map((c) => c?.length ?? 0).fold(0, (a, b) => a > b ? a : b);

  String encode() {
    final cols = {'t': time, 'd': distance, 'lat': lat, 'lon': lon, 'alt': altitude, 'hr': hr, 'cad': cadence};
    return base64.encode(gzip.encode(utf8.encode(jsonEncode({for (final e in cols.entries) if (e.value != null) e.key: e.value}))));
  }

  static Track decode(String points) {
    final j = jsonDecode(utf8.decode(gzip.decode(base64.decode(points)))) as Map<String, dynamic>;
    List<double?>? d(String k) => (j[k] as List?)?.map((v) => (v as num?)?.toDouble()).toList();
    List<int?>? i(String k) => (j[k] as List?)?.map((v) => (v as num?)?.round()).toList();
    return Track(time: i('t'), distance: d('d'), lat: d('lat'), lon: d('lon'), altitude: d('alt'), hr: i('hr'), cadence: d('cad'));
  }
}
