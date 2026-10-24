import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../../data/backup.dart';
import '../../data/db.dart';
import '../../data/sync.dart';

/// More > Backup / Restore. Export opens the share sheet; restore asks replace or merge, then confirms.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.db, required this.engine});

  final AppDb db;
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
    } catch (e) {
      if (mounted) _say(e is FormatException ? 'Restore failed: ${e.message}' : 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        final file = File('${(await getTemporaryDirectory()).path}/timburr-backup-$stamp.json');
        await file.writeAsString(await Backup(widget.db).export());
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
        await BackupReminder.markExported();
      });

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
      await Backup(widget.db).restore(utf8.decode(await picked.readAsBytes()), replace: replace);
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

  final VoidCallback onOpen;

  @override
  State<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends State<BackupReminderCard> {
  late final Future<bool> _due = BackupReminder.due();
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
                  onTap: widget.onOpen,
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
