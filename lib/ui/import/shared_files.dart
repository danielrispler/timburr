import 'dart:convert';

import 'package:flutter/services.dart';

/// A file another app shared to Timburr: its name and text.
typedef SharedFile = ({String name, String text});

List<SharedFile> _decode(Object? raw) => [
      for (final f in (raw as List? ?? const []).cast<Map>()) (name: f['name'] as String, text: utf8.decode(f['bytes'] as Uint8List, allowMalformed: true)),
    ];

/// Files shared from the Android share sheet. The platform side is MainActivity.kt (channel `timburr/share`).
class ShareIntake {
  ShareIntake(this.onFiles) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') onFiles(_decode(call.arguments));
    });
  }

  static const _channel = MethodChannel('timburr/share');
  final void Function(List<SharedFile>) onFiles;

  /// Files that opened the app; call once the UI is up. Does nothing off Android.
  Future<void> checkLaunch() async {
    try {
      final files = _decode(await _channel.invokeMethod('takeShared'));
      if (files.isNotEmpty) onFiles(files);
    } on MissingPluginException {
      // not Android
    }
  }
}
