/// Google Health stats of one strength workout; any can be missing.
typedef HealthStats = ({int? avgHr, int? calories, int? activeSec, int? effort, int? cardioLoad});

/// One recognised text line with its box, in image pixels.
typedef OcrLine = ({String text, double left, double top, double bottom});

/// Reads [HealthStats] from OCR lines of a Google Health workout screenshot.
/// Lines whose vertical centre falls inside another line's box share a row, so a label meets its value.
HealthStats parseHealth(List<OcrLine> lines) {
  final rows = <List<OcrLine>>[];
  for (final line in [...lines]..sort((a, b) => a.top.compareTo(b.top))) {
    final mid = (line.top + line.bottom) / 2;
    final row = rows.where((r) => r.any((o) => mid >= o.top && mid <= o.bottom || (o.top + o.bottom) / 2 >= line.top && (o.top + o.bottom) / 2 <= line.bottom)).firstOrNull;
    row == null ? rows.add([line]) : row.add(line);
  }
  final texts = [for (final r in rows) ([...r]..sort((a, b) => a.left.compareTo(b.left))).map((o) => o.text).join(' ')];
  int? find(RegExp re) {
    for (final t in texts) {
      final m = re.firstMatch(t);
      if (m != null) return int.parse(m[1]!.replaceAll(',', ''));
    }
    return null;
  }

  int? duration() {
    for (final t in texts) {
      final m = RegExp(r'(?:(\d+)h\s*)?(\d+)m(?:\s*(\d+)s)?').firstMatch(t);
      if (m != null) return int.parse(m[1] ?? '0') * 3600 + int.parse(m[2]!) * 60 + int.parse(m[3] ?? '0');
    }
    return null;
  }

  return (
    avgHr: find(RegExp(r'(\d+)\s*bpm', caseSensitive: false)),
    calories: find(RegExp(r'(\d[\d,]*)\s*cal\b', caseSensitive: false)),
    activeSec: duration(),
    effort: find(RegExp(r'effort\D*?(\d+)', caseSensitive: false)),
    cardioLoad: find(RegExp(r'cardio load\D*?(\d+)', caseSensitive: false)),
  );
}
