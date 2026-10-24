import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/catalog.dart';
import '../core/theme.dart';

final _downloads = <String, Future<File?>>{};

/// Photo [frame] of a library exercise, downloaded once into the cache dir. Local only: not synced or backed up.
/// Null when offline or missing; a failed download is retried next time it is asked for.
Future<File?> _photo(String libraryId, int frame) => _downloads['$libraryId/$frame'] ??= () async {
      final f = File('${(await getApplicationCacheDirectory()).path}/exercise_images/${libraryId}_$frame.jpg');
      if (await f.exists()) return f;
      try {
        final res = await (await HttpClient().getUrl(exerciseImageUrl(libraryId, frame))).close();
        if (res.statusCode != 200) throw HttpException('${res.statusCode}');
        await f.parent.create(recursive: true);
        final part = File('${f.path}.part');
        await res.pipe(part.openWrite());
        return await part.rename(f.path);
      } catch (_) {
        _downloads.remove('$libraryId/$frame');
        return null;
      }
    }();

/// 52 px square thumbnail: the start photo, or the muscle icon for custom exercises and while loading.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb(this.entry, {super.key});

  final CatalogEntry? entry;

  @override
  Widget build(BuildContext context) {
    final fallback = IconTile(muscleIcon(entry?.muscles.firstOrNull));
    final id = entry?.libraryId;
    if (id == null) return fallback;
    return FutureBuilder(
      future: _photo(id, 0),
      builder: (_, snap) => snap.data == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(snap.data!, width: 52, height: 52, fit: BoxFit.cover),
            ),
    );
  }
}

/// Large photo that flips between the start and end positions, like a slow animation. Nothing for custom exercises.
class ExerciseHero extends StatefulWidget {
  const ExerciseHero(this.entry, {super.key});

  final CatalogEntry entry;

  @override
  State<ExerciseHero> createState() => _ExerciseHeroState();
}

class _ExerciseHeroState extends State<ExerciseHero> {
  late final _frames = widget.entry.libraryId == null
      ? Future.value(const <File>[])
      : Future.wait([_photo(widget.entry.libraryId!, 0), _photo(widget.entry.libraryId!, 1)])
          .then((fs) => [for (final f in fs) ?f]);
  int _i = 0;
  late final _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) => setState(() => _i++));

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _frames,
        builder: (_, snap) {
          final frames = snap.data ?? const [];
          if (frames.isEmpty) return const SizedBox.shrink();
          _timer; // start flipping once there is something to show
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Image.file(frames[_i % frames.length], key: ValueKey(_i % frames.length), fit: BoxFit.cover),
                ),
              ),
            ),
          );
        },
      );
}
