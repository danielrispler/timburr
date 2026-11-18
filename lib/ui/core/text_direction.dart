import 'package:flutter/material.dart';

final _letter = RegExp(r'\p{L}', unicode: true);
final _rtl = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');

/// Right to left when [text]'s first letter is Hebrew or Arabic, so a note written in Hebrew aligns right.
TextDirection textDirectionOf(String text) {
  final first = _letter.firstMatch(text)?.group(0);
  return first != null && _rtl.hasMatch(first) ? TextDirection.rtl : TextDirection.ltr;
}

/// Rebuilds [builder] with [controller]'s text direction as it is typed.
class AutoDirection extends StatelessWidget {
  const AutoDirection({super.key, required this.controller, required this.builder});

  final TextEditingController controller;
  final Widget Function(TextDirection direction) builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) => builder(textDirectionOf(controller.text)));
}
