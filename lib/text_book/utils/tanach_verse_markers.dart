class TanachVerseMarkerResult {
  final String? verseNumber;
  final String text;

  const TanachVerseMarkerResult({
    required this.verseNumber,
    required this.text,
  });
}

final RegExp _leadingVerseMarkerPattern = RegExp(
  r"""^\s*(?:<(?:small|span)\b[^>]*>\s*)?\(\s*([\u0590-\u05FF"׳״']{1,8})\s*\)(?:\s*</(?:small|span)>)?\s*""",
  caseSensitive: false,
);

/// מחלץ סימון פסוק עברי מתחילת שורת תנ"ך ומחזיר טקסט ללא הסימון.
TanachVerseMarkerResult extractLeadingTanachVerseMarker(String text) {
  final match = _leadingVerseMarkerPattern.firstMatch(text);
  if (match == null) {
    return TanachVerseMarkerResult(verseNumber: null, text: text);
  }

  return TanachVerseMarkerResult(
    verseNumber: match.group(1)?.trim(),
    text: text.substring(match.end),
  );
}
