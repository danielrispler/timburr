import 'cardio.dart';
import 'recording.dart';
import 'run_file.dart';
import 'strava_gpx.dart';
import 'strava_tcx.dart';

/// Reads a .tcx or .gpx file by its extension.
ParsedFile parseRunFile(String fileName, String xml) =>
    fileName.toLowerCase().endsWith('.gpx') ? parseStravaGpx(fileName, xml) : parseStravaTcx(fileName, xml);

/// What importing [files] would do, for the preview before anything is saved.
class StravaPreview {
  StravaPreview(this.files, this.outcomes);
  final List<ParsedFile> files;
  final Map<ParsedFile, IngestOutcome> outcomes; // an entry per readable file

  Iterable<ParsedFile> get _readable => files.where((f) => f.recording != null);
  int get readable => _readable.length;
  int get skipped => files.length - readable;
  int get treadmill => _readable.where((f) => f.recording!.type == 'treadmill').length;
  int get withMap => _readable.where((f) => f.recording!.type == 'run' && f.recording!.hasRoute).length;
  int get noRoute => _readable.where((f) => f.recording!.type == 'run' && !f.recording!.hasRoute).length;

  int _count(IngestOutcome o) => outcomes.values.where((v) => v == o).length;
  int get newRuns => _count(IngestOutcome.created);
  /// Files that overlap a Run already in Timburr and only fill what it lacks.
  int get merged => _count(IngestOutcome.merged);
  int get alreadyImported => _count(IngestOutcome.unchanged);
}

/// What Save would do with [files], in order, writing nothing. Each file is dry-run against the Runs already stored; one that would be new but overlaps or repeats an
/// earlier file of the same pick would merge into it (or be skipped) once that file is saved, so it counts that way.
Future<StravaPreview> previewStrava(CardioStore store, List<ParsedFile> files) async {
  final outcomes = <ParsedFile, IngestOutcome>{};
  final pending = <Recording>[]; // files that would create a Run
  for (final f in files) {
    final r = f.recording;
    if (r == null) continue;
    var outcome = (await store.ingest(r, dryRun: true)).outcome;
    if (outcome == IngestOutcome.created) {
      Recording? earlier;
      for (final p in pending) {
        if (p.source == r.source && p.externalId != null && p.externalId == r.externalId) {
          outcome = IngestOutcome.unchanged;
          break;
        }
        if (earlier == null && p.start.isBefore(r.end) && r.start.isBefore(p.end)) earlier = p;
      }
      if (outcome == IngestOutcome.created && earlier != null) outcome = IngestOutcome.merged;
      if (outcome == IngestOutcome.created) pending.add(r);
    }
    outcomes[f] = outcome;
  }
  return StravaPreview(files, outcomes);
}

/// Saves every readable file in order (so files that overlap each other merge too) and returns how many Runs were created and merged.
Future<({int created, int merged})> importStrava(CardioStore store, List<ParsedFile> files) async {
  var created = 0, merged = 0;
  for (final f in files) {
    if (f.recording == null) continue;
    switch ((await store.ingest(f.recording!)).outcome) {
      case IngestOutcome.created:
        created++;
      case IngestOutcome.merged:
        merged++;
      case IngestOutcome.unchanged:
    }
  }
  return (created: created, merged: merged);
}
