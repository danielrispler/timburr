import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/backup.dart';
import '../../data/catalog.dart';
import '../../data/importer.dart';
import '../../data/stats.dart';
import '../../data/sync.dart';
import '../../data/error_log.dart';
import '../core/theme.dart';

/// More > Backup / Restore. Exports open the share sheet; restore asks replace or merge, then confirms.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.catalog, required this.engine});

  final Catalog catalog;
  final SyncEngine? engine;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e, st) {
      reportError('backup', e, st);
      if (mounted) _say(e is FormatException ? 'Restore failed: ${e.message}' : 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        final file = File('${(await getTemporaryDirectory()).path}/timburr-backup-$stamp.json');
        await file.writeAsString(await Backup(widget.catalog.db).export());
        final result = await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
        // Some Android versions report unavailable even when the share went through.
        if (result.status != ShareResultStatus.dismissed) await BackupReminder.markExported();
      });

  /// Asks for a range, then shares those workouts and cardio in the import format. Not a backup, so the reminder stays.
  Future<void> _exportWorkouts() async {
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    final now = DateTime.now(), today = dayOf(now), monday = mondayOf(now);
    final range = await showDialog<(DateTime?, DateTime?, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export which workouts?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (today, DateTime(today.year, today.month, today.day + 1), day(today))),
            child: const ListTile(title: Text('Today')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (
              monday,
              DateTime(monday.year, monday.month, monday.day + 7),
              '${day(monday)}-to-${day(DateTime(monday.year, monday.month, monday.day + 6))}',
            )),
            child: const ListTile(title: Text('This week')),
          ),
          SimpleDialogOption(
            onPressed: () async {
              final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: today);
              if (picked == null || !context.mounted) return;
              final end = picked.end;
              Navigator.pop(context, (picked.start, DateTime(end.year, end.month, end.day + 1), '${day(picked.start)}-to-${day(end)}'));
            },
            child: const ListTile(title: Text('Pick dates…')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (null, null, 'all')),
            child: const ListTile(title: Text('All workouts')),
          ),
        ],
      ),
    );
    if (range == null || !mounted) return;
    final (from, to, label) = range;
    await _run(() async {
      final file = File('${(await getTemporaryDirectory()).path}/timburr-workouts-$label.json');
      await file.writeAsString(await Importer(widget.catalog.db, widget.catalog).export(from: from, to: to));
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
    });
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile();
    if (picked == null || !mounted) return;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Restore how?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: const ListTile(
                title: Text('Replace'), subtitle: Text('Your data becomes the backup. Rows not in it are deleted (soft, can be undone).')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, false),
            child: const ListTile(title: Text('Merge'), subtitle: Text('Adds the backup to your data. Where both have a row, the newer edit wins.')),
          ),
        ],
      ),
    );
    if (replace == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(replace ? 'Replace all data?' : 'Merge backup?'),
        content: Text('${picked.name} will be restored here, then synced to Supabase.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(replace ? 'Replace' : 'Merge')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await Backup(widget.catalog.db).restore(utf8.decode(await picked.readAsBytes()), replace: replace);
      if (mounted) _say('Backup restored.');
      widget.engine?.sync();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Backup / Restore')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              children: [
                if (_busy) const LinearProgressIndicator(),
                TileGroup(children: [
                ListTile(
                  leading: const IconTile(Icons.upload_file),
                  title: const Text('Export backup'),
                  subtitle: const Text('All data as one JSON file, via the share sheet'),
                  enabled: !_busy,
                  onTap: _export,
                ),
                ListTile(
                  leading: const IconTile(Icons.ios_share),
                  title: const Text('Export workouts'),
                  subtitle: const Text('Today, this week, picked dates or all, in the import format'),
                  enabled: !_busy,
                  onTap: _exportWorkouts,
                ),
                ListTile(
                  leading: const IconTile(Icons.restore),
                  title: const Text('Restore backup'),
                  subtitle: const Text('Pick a backup file, then replace or merge'),
                  enabled: !_busy,
                  onTap: _restore,
                ),
                ]),
              ],
            ),
          ),
        ),
      );
}

/// Small dismissible Home card, shown when the last export is more than 14 days old. Never a popup.
class BackupReminderCard extends StatefulWidget {
  const BackupReminderCard({super.key, required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  State<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends State<BackupReminderCard> {
  late Future<bool> _due = BackupReminder.due();
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _due,
        builder: (context, snap) => snap.data != true || _dismissed
            ? const SizedBox.shrink()
            : TileGroup(children: [
                ListTile(
                  leading: const IconTile(Icons.backup),
                  title: const Text('Back up your data'),
                  subtitle: const Text('No export in the last 14 days'),
                  onTap: () async {
                    await widget.onOpen();
                    if (mounted) setState(() => _due = BackupReminder.due());
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Dismiss',
                    onPressed: () {
                      setState(() => _dismissed = true);
                      BackupReminder.markDismissed();
                    },
                  ),
                ),
              ]),
      );
}
