import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/error_log.dart';
import '../../data/run_file.dart';
import '../../data/strava_import.dart';
import '../core/theme.dart';
import 'shared_files.dart';

/// Pick Strava TCX or GPX files (or open ones shared from another app), see what they would add, then save them all through the Run store.
class StravaImportScreen extends StatefulWidget {
  const StravaImportScreen({super.key, required this.cardio, this.shared});

  final CardioStore cardio;

  /// Files shared from another app; read straight away.
  final List<SharedFile>? shared;

  @override
  State<StravaImportScreen> createState() => _StravaImportScreenState();
}

class _StravaImportScreenState extends State<StravaImportScreen> {
  StravaPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.shared != null) _load(Stream.fromIterable(widget.shared!), widget.shared!.length);
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    picked.sort((a, b) => a.name.compareTo(b.name));
    await _load(() async* {
      for (final f in picked) {
        yield (name: f.name, text: utf8.decode(await f.readAsBytes(), allowMalformed: true));
      }
    }(), picked.length);
  }

  Future<void> _load(Stream<SharedFile> files, int count) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final parsed = <ParsedFile>[];
      await for (final f in files) {
        parsed.add(parseRunFile(f.name, f.text));
        await Future<void>.delayed(Duration.zero); // let the progress bar draw between big files
      }
      final preview = await previewStrava(widget.cardio, parsed);
      if (mounted) setState(() => _preview = preview);
    } catch (e, st) {
      reportError('strava_preview', e, st, {'files': count});
      if (mounted) setState(() => _error = 'Could not read the files: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context), nav = Navigator.of(context);
    try {
      final r = await importStrava(widget.cardio, _preview!.files);
      messenger.showSnackBar(SnackBar(content: Text('Imported ${r.created} Runs${r.merged > 0 ? ', ${r.merged} filled into existing Runs' : ''}')));
      nav.pop();
    } catch (e, st) {
      reportError('strava_import', e, st, {'files': _preview!.files.length});
      setState(() => _error = 'Nothing more was saved: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    final colors = Theme.of(context).colorScheme;
    final notes = [
      if (p != null)
        for (final f in p.files)
          if (f.skipReason != null || f.warnings.isNotEmpty) f,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Import Strava runs')),
      bottomNavigationBar: BottomAction(children: [
        if (p != null && p.newRuns + p.merged > 0)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(p.merged > 0 ? 'Import ${p.newRuns} Runs, fill ${p.merged}' : 'Import ${p.newRuns} Runs'),
          ),
        FilledButton.tonalIcon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.folder_open), label: Text(p == null ? 'Pick TCX or GPX files' : 'Pick other files')),
      ]),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (p == null && _error == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pick the TCX or GPX files from a Strava export. Nothing is saved until you confirm. '
                  'Files that overlap a Run you already have only fill what it is missing, and picking a file twice changes nothing.'),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: colors.error))),
          if (p != null) ...[
            TileGroup(title: '${p.files.length} files', children: [
              _count('New Runs', p.newRuns),
              _count('Runs with a map', p.withMap),
              _count('Runs without a route', p.noRoute),
              if (p.merged > 0) _count('Fill into a Run you already have', p.merged),
              if (p.alreadyImported > 0) _count('Already imported', p.alreadyImported),
              _count('Skipped', p.skipped),
            ]),
            if (notes.isNotEmpty)
              TileGroup(title: 'Notes', children: [
                for (final f in notes)
                  ListTile(
                    dense: true,
                    title: Text(f.name, textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(f.skipReason != null ? 'Skipped: ${f.skipReason}' : f.warnings.join('. '),
                        style: f.skipReason != null ? TextStyle(color: colors.error) : null),
                  ),
              ]),
          ],
        ],
      ),
    );
  }

  Widget _count(String label, int n) => ListTile(dense: true, title: Text(label), trailing: Text('$n'));
}
