import 'package:flutter/material.dart';

import '../../data/cardio.dart';
import '../../data/db.dart';
import '../../data/shoes.dart';
import '../core/theme.dart';

/// The Progress tile that opens the shoes list.
class ShoesTile extends StatelessWidget {
  const ShoesTile({super.key, required this.store, required this.runs});

  final CardioStore store;
  final Stream<List<CardioData>> runs;

  @override
  Widget build(BuildContext context) => TileGroup(children: [
        ListTile(
          leading: const Icon(Icons.directions_run),
          title: const Text('Shoes'),
          subtitle: const Text('Distance on each pair'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShoesScreen(store: store, runs: runs))),
        ),
      ]);
}

String _km(double km) => '${km.toStringAsFixed(km < 100 ? 1 : 0)} km';

/// Every pair of shoes with its total distance. Add one, make one the default for new Runs, retire one that is worn out.
class ShoesScreen extends StatelessWidget {
  const ShoesScreen({super.key, required this.store, required this.runs});

  final CardioStore store;
  final Stream<List<CardioData>> runs;

  Future<void> _add(BuildContext context) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name != null && name.trim().isNotEmpty) await store.shoes.add(name);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Shoes')),
        floatingActionButton: FloatingActionButton(tooltip: 'Add shoes', onPressed: () => _add(context), child: const Icon(Icons.add)),
        body: StreamBuilder<List<Shoe>>(
          stream: store.shoes.watchAll(),
          builder: (context, shoeSnap) => StreamBuilder<List<CardioData>>(
            stream: runs,
            builder: (context, runSnap) {
              final shoes = shoeSnap.data, all = runSnap.data;
              if (shoes == null || all == null) return const Center(child: CircularProgressIndicator());
              if (shoes.isEmpty) return const Center(child: Text('Add a pair of shoes, then give it to your Runs.'));
              final km = shoeTotals(all);
              return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                for (final s in shoes)
                  ListTile(
                    key: ValueKey(s.id),
                    title: Text(s.name),
                    subtitle: Text([_km(km[s.id] ?? 0), if (s.isDefault) 'Default for new Runs', if (s.retiredAt != null) 'Retired'].join(' · ')),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) => v == 'default' ? store.shoes.setDefault(s.id) : store.shoes.setRetired(s.id, s.retiredAt == null),
                      itemBuilder: (_) => [
                        if (s.retiredAt == null && !s.isDefault) const PopupMenuItem(value: 'default', child: Text('Use for new Runs')),
                        PopupMenuItem(value: 'retire', child: Text(s.retiredAt == null ? 'Retire' : 'Bring back')),
                      ],
                    ),
                  ),
              ]);
            },
          ),
        ),
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add shoes'),
        content: TextField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Add')),
        ],
      );
}

/// The Run page's shoe line: the pair this Run was on, and a dialog to change it. Retired pairs are offered only while a Run is on one.
class ShoePicker extends StatelessWidget {
  const ShoePicker({super.key, required this.store, required this.run});

  final CardioStore store;
  final CardioData run;

  Future<void> _pick(BuildContext context, List<Shoe> shoes) async {
    const none = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(title: const Text('Shoes'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, none), child: const Text('No shoes')),
        for (final s in shoes)
          if (s.retiredAt == null || s.id == run.shoeId) SimpleDialogOption(onPressed: () => Navigator.pop(context, s.id), child: Text(s.retiredAt == null ? s.name : '${s.name} (retired)')),
      ]),
    );
    if (choice == null || choice == (run.shoeId ?? none)) return;
    await store.edit(run.id, {'shoe_id': choice == none ? null : choice});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Shoe>>(
        stream: store.shoes.watchAll(),
        builder: (context, snap) {
          final shoes = snap.data;
          if (shoes == null || (shoes.isEmpty && run.shoeId == null)) return const SizedBox.shrink(); // no shoes added yet: nothing to pick
          final current = shoes.where((s) => s.id == run.shoeId).firstOrNull;
          return TileGroup(children: [
            ListTile(
              leading: const Icon(Icons.directions_run),
              title: const Text('Shoes'),
              subtitle: Text(current?.name ?? 'None'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pick(context, shoes),
            ),
          ]);
        },
      );
}
