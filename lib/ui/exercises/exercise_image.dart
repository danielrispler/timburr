import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/catalog.dart';
import '../core/theme.dart';

final _downloads = <String, Future<File?>>{};
final _http = HttpClient();
var _running = 0;
final _waiting = <Completer<void>>[];

/// Thumbnail or GIF of a library exercise, downloaded once into the cache dir. Local only: not synced or backed up.
/// Null when offline or missing. A failure is remembered until the app restarts, so rebuilds don't refetch.
Future<File?> _media(String media, {bool gif = false}) => _downloads['$media/$gif'] ??= () async {
      final f = File('${(await getApplicationCacheDirectory()).path}/exercise_media/$media.${gif ? 'gif' : 'jpg'}');
      if (await f.exists()) return f;
      // At most 4 downloads at once, so a fast scroll doesn't open hundreds of sockets.
      if (_running >= 4) await (_waiting..add(Completer())).last.future;
      _running++;
      try {
        final res = await (await _http.getUrl(exerciseMediaUrl(media, gif: gif))).close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          return null;
        }
        await f.parent.create(recursive: true);
        final part = File('${f.path}.part');
        await res.pipe(part.openWrite());
        return await part.rename(f.path);
      } catch (_) {
        return null;
      } finally {
        _running--;
        if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
      }
    }();

/// 52 px square thumbnail: the Gym visual still, or the muscle icon for custom exercises and while loading.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb(this.entry, {super.key});

  final CatalogEntry? entry;

  @override
  Widget build(BuildContext context) {
    final fallback = IconTile(muscleIcon(entry?.muscles.firstOrNull));
    final media = entry?.media;
    if (media == null) return fallback;
    return FutureBuilder(
      future: _media(media),
      builder: (_, snap) => snap.data == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(snap.data!, width: 52, height: 52, fit: BoxFit.cover),
            ),
    );
  }
}

/// Large looping animation of the exercise, with the credit its licence requires. Nothing for custom exercises.
class ExerciseHero extends StatefulWidget {
  const ExerciseHero(this.entry, {super.key});

  final CatalogEntry entry;

  @override
  State<ExerciseHero> createState() => _ExerciseHeroState();
}

class _ExerciseHeroState extends State<ExerciseHero> {
  late final _gif = widget.entry.media == null ? Future<File?>.value() : _media(widget.entry.media!, gif: true);

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _gif,
        builder: (context, snap) {
          final gif = snap.data;
          if (gif == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                // White behind the GIF, which has a white background, so it doesn't box out in dark mode.
                child: ColoredBox(
                  color: Colors.white,
                  // The GIFs are 180 px; larger only blurs them.
                  child: SizedBox.square(dimension: 240, child: Image.file(gif, fit: BoxFit.contain)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('© Gym visual — https://gymvisual.com/', style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          );
        },
      );
}
