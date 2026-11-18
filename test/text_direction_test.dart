import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timburr/ui/core/text_direction.dart';

void main() {
  test('the first letter decides the direction', () {
    expect(textDirectionOf('לכל רגל ומשקולת בכל יד'), TextDirection.rtl);
    expect(textDirectionOf('3 סטים, seat 4'), TextDirection.rtl); // digits and spaces are skipped
    expect(textDirectionOf('seat 4 · מושב'), TextDirection.ltr);
    expect(textDirectionOf(''), TextDirection.ltr);
    expect(textDirectionOf('80'), TextDirection.ltr);
  });
}
