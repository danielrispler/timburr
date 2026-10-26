import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'error_log.dart';

const restChoices = [60, 90, 120, 150];

/// Rest timer state: offered after a set is done, counts down once a duration is picked.
/// The alarm itself lives behind [schedule]/[cancel] so it fires with the screen off.
class RestTimer extends ChangeNotifier {
  RestTimer(this._catalog, {required this.schedule, required this.cancel});

  final Catalog _catalog;
  final Future<void> Function(Duration) schedule;
  final Future<void> Function() cancel;

  String? _exerciseId;
  bool _offered = false;
  int? highlightSec;
  DateTime? _endsAt;
  Timer? _hide, _tick;

  /// Choices visible (auto-hide after ~5 s if untouched).
  bool get offered => _offered;

  Duration? get remaining {
    final left = _endsAt?.difference(DateTime.now());
    return left == null || left.isNegative ? null : left;
  }

  Future<void> offer(String exerciseId) async {
    _exerciseId = exerciseId;
    _offered = true;
    highlightSec = (await _catalog.byId(exerciseId))?.lastRestSec;
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), dismiss);
    notifyListeners();
  }

  void dismiss() {
    _hide?.cancel();
    _offered = false;
    notifyListeners();
  }

  Future<void> start(int sec) async {
    final id = _exerciseId;
    _endsAt = DateTime.now().add(Duration(seconds: sec));
    if (id != null) await _catalog.setLastRest(id, sec);
    try {
      await cancel();
      await schedule(Duration(seconds: sec));
    } catch (e, st) {
      reportError('rest_timer.schedule', e, st); // the in-app countdown still runs
    }
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (remaining == null) t.cancel();
      notifyListeners();
    });
    dismiss();
  }

  Future<void> stop() async {
    _tick?.cancel();
    _endsAt = null;
    await cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
