import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class ContinuousReadingParagraphLine {
  final int lineIndex;
  final String text;
  final String? verseNumber;
  final List<InlineSpan>? inlineSpans;
  final TextStyle style;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    required this.text,
    required this.style,
    this.verseNumber,
    this.inlineSpans,
  });
}

List<InlineSpan> buildInlineHtmlSpans(
  String htmlText,
  TextStyle baseStyle,
) {
  final fragment = html_parser.parseFragment(htmlText);
  return _nodesToSpans(fragment.nodes, baseStyle);
}

class ContinuousReadingParagraph extends StatefulWidget {
  final List<ContinuousReadingParagraphLine> lines;
  final TextStyle baseStyle;
  final ValueChanged<int> onLineTap;
  final ValueChanged<int>? onLineSecondaryTap;
  final TextDirection textDirection;
  final TextAlign textAlign;

  const ContinuousReadingParagraph({
    super.key,
    required this.lines,
    required this.baseStyle,
    required this.onLineTap,
    this.onLineSecondaryTap,
    this.textDirection = TextDirection.rtl,
    this.textAlign = TextAlign.justify,
  });

  @override
  State<ContinuousReadingParagraph> createState() =>
      _ContinuousReadingParagraphState();
}

class _ContinuousReadingParagraphState
    extends State<ContinuousReadingParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(covariant ContinuousReadingParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameLineOrder(oldWidget.lines, widget.lines)) {
      _rebuildRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final markerAnchors = <_VerseMarkerAnchor>[];
    var textOffset = 0;

    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final hasNext = i < widget.lines.length - 1;
      final lineSpans = line.inlineSpans ?? [TextSpan(text: line.text)];
      final lineStartOffset = textOffset;

      for (final span in lineSpans) {
        spans.add(_withRecognizer(span, _recognizers[i], line.style));
        textOffset += _plainTextLength(span);
      }

      final verseNumber = line.verseNumber?.trim();
      if (verseNumber != null && verseNumber.isNotEmpty) {
        markerAnchors.add(
          _VerseMarkerAnchor(
            number: verseNumber,
            lineIndex: line.lineIndex,
            textOffset: lineStartOffset,
          ),
        );
      }

      if (hasNext) {
        spans.add(TextSpan(text: ' ', style: line.style));
        textOffset += 1;
      }
    }

    final textSpan = TextSpan(style: widget.baseStyle, children: spans);
    return LayoutBuilder(
      builder: (context, constraints) {
        final markerStyle = widget.baseStyle.copyWith(
          fontSize: (widget.baseStyle.fontSize ?? 18) * 0.68,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.0,
        );
        final hasMarkers = markerAnchors.isNotEmpty;
        final markerGap = hasMarkers ? 6.0 : 0.0;
        final textScaler = MediaQuery.textScalerOf(context);

        if (!hasMarkers || !constraints.hasBoundedWidth) {
          return Text.rich(
            textSpan,
            textDirection: widget.textDirection,
            textAlign: _effectiveTextAlign(
              textSpan: textSpan,
              maxWidth: constraints.maxWidth,
              textScaler: textScaler,
            ),
          );
        }

        const baseMarkerGutterWidth = 28.0;
        final initialTextMaxWidth =
            (constraints.maxWidth - baseMarkerGutterWidth - markerGap)
                .clamp(0.0, double.infinity);
        final initialGroups = _markerGroupsForText(
          textSpan: textSpan,
          anchors: markerAnchors,
          markerStyle: markerStyle,
          maxWidth: initialTextMaxWidth,
          textScaler: textScaler,
        );
        final markerGutterWidth = _markerGutterWidthForGroups(
          initialGroups,
        ).clamp(baseMarkerGutterWidth, double.infinity);
        final textMaxWidth =
            (constraints.maxWidth - markerGutterWidth - markerGap)
                .clamp(0.0, double.infinity);
        final markerGroups = markerGutterWidth > baseMarkerGutterWidth
            ? _markerGroupsForText(
                textSpan: textSpan,
                anchors: markerAnchors,
                markerStyle: markerStyle,
                maxWidth: textMaxWidth,
                textScaler: textScaler,
              )
            : initialGroups;

        return Directionality(
          textDirection: widget.textDirection,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: markerGutterWidth,
                height: _textHeight(
                  textSpan: textSpan,
                  maxWidth: textMaxWidth,
                  textScaler: textScaler,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final group in markerGroups)
                      Positioned(
                        top: group.top,
                        left: 0,
                        child: _VerseMarkerGrid(
                          group: group,
                          markerStyle: markerStyle,
                          onMarkerTap: widget.onLineTap,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: markerGap),
              Expanded(
                child: Text.rich(
                  textSpan,
                  textDirection: widget.textDirection,
                  textAlign: _effectiveTextAlign(
                    textSpan: textSpan,
                    maxWidth: textMaxWidth,
                    textScaler: textScaler,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  TextAlign _effectiveTextAlign({
    required InlineSpan textSpan,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    if (widget.textAlign != TextAlign.justify || !maxWidth.isFinite) {
      return widget.textAlign;
    }

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.start,
      textDirection: widget.textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    final visualLineCount = textPainter.computeLineMetrics().length;
    textPainter.dispose();

    return visualLineCount <= 1 ? TextAlign.start : widget.textAlign;
  }

  List<_PositionedVerseMarkerGroup> _markerGroupsForText({
    required InlineSpan textSpan,
    required List<_VerseMarkerAnchor> anchors,
    required TextStyle markerStyle,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    if (anchors.isEmpty || !maxWidth.isFinite) {
      return const [];
    }

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.start,
      textDirection: widget.textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);

    final groups = <_VerseMarkerGroup>[];
    final fullTextLength = textPainter.plainText.length;
    final visualLines = _visualLinesForText(
      textPainter: textPainter,
      lineMetrics: textPainter.computeLineMetrics(),
      textLength: fullTextLength,
    );

    for (final anchor in anchors) {
      if (fullTextLength == 0) {
        continue;
      }
      final start = anchor.textOffset.clamp(0, fullTextLength - 1);
      final visualLine = _visualLineForOffset(visualLines, start);
      final top = visualLine?.top ?? 0.0;
      final height = visualLine?.height ?? 0.0;
      final existingIndex =
          groups.indexWhere((group) => (group.lineTop - top).abs() < 1.0);

      if (existingIndex >= 0) {
        groups[existingIndex].markers.add(anchor);
      } else {
        groups.add(
          _VerseMarkerGroup(
            lineTop: top,
            lineHeight: height,
            markers: [anchor],
          ),
        );
      }
    }
    textPainter.dispose();

    final markerHeight = _textStyleLineHeight(
      style: markerStyle,
      textScaler: textScaler,
    );
    return [
      for (final group in groups)
        group.centered(
          markerGroupHeight: _markerGroupHeight(
            markerHeight: markerHeight,
            count: group.markers.length,
          ),
        ),
    ];
  }

  double _markerGutterWidthForGroups(
    List<_PositionedVerseMarkerGroup> groups,
  ) {
    if (groups.isEmpty) {
      return 0;
    }

    final maxColumns = groups
        .map((group) => _markerRowSizes(group.markers.length).reduce(
              (value, element) => value > element ? value : element,
            ))
        .reduce((value, element) => value > element ? value : element);
    final markerCellWidth = groups
        .map(_VerseMarkerGrid.markerCellWidthForGroup)
        .reduce((value, element) => value > element ? value : element);
    return maxColumns * markerCellWidth +
        (maxColumns - 1) * _VerseMarkerGrid.markerColumnGap;
  }

  double _markerGroupHeight({
    required double markerHeight,
    required int count,
  }) {
    final rowCount = _markerRowSizes(count).length;
    return rowCount * markerHeight +
        (rowCount - 1) * _VerseMarkerGrid.markerRowGap;
  }

  List<int> _markerRowSizes(int count) {
    return switch (count) {
      <= 0 => const <int>[],
      1 => const [1],
      2 => const [1, 1],
      3 => const [2, 1],
      4 => const [2, 2],
      5 => const [3, 2],
      _ => [
          for (var remaining = count; remaining > 0; remaining -= 3)
            remaining >= 3 ? 3 : remaining,
        ],
    };
  }

  List<_VisualTextLine> _visualLinesForText({
    required TextPainter textPainter,
    required List<LineMetrics> lineMetrics,
    required int textLength,
  }) {
    final lines = <_VisualTextLine>[];
    if (textLength <= 0 || lineMetrics.isEmpty) {
      return lines;
    }

    var offset = 0;
    while (offset < textLength && lines.length < lineMetrics.length) {
      var range = textPainter.getLineBoundary(TextPosition(offset: offset));
      if (range.start < offset && offset > 0) {
        range = textPainter.getLineBoundary(TextPosition(offset: offset + 1));
      }
      final start = range.start < offset ? offset : range.start;
      final end = range.end <= start ? start + 1 : range.end;
      final metric = lineMetrics[lines.length];
      lines.add(
        _VisualTextLine(
          start: start,
          end: end.clamp(start + 1, textLength).toInt(),
          top: metric.baseline - metric.ascent,
          height: metric.height,
        ),
      );
      offset = end;
    }

    return lines;
  }

  _VisualTextLine? _visualLineForOffset(
    List<_VisualTextLine> lines,
    int offset,
  ) {
    if (lines.isEmpty) {
      return null;
    }
    for (final line in lines) {
      if (offset >= line.start && offset < line.end) {
        return line;
      }
    }
    return lines.last;
  }

  double _textStyleLineHeight({
    required TextStyle style,
    required TextScaler textScaler,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(text: 'א', style: style),
      textDirection: widget.textDirection,
      textScaler: textScaler,
    )..layout();
    final height = textPainter.height;
    textPainter.dispose();
    return height;
  }

  double _textHeight({
    required InlineSpan textSpan,
    required double maxWidth,
    required TextScaler textScaler,
  }) {
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.start,
      textDirection: widget.textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final height = textPainter.height;
    textPainter.dispose();
    return height;
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    for (var i = 0; i < widget.lines.length; i++) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onLineTap(widget.lines[i].lineIndex);
      if (widget.onLineSecondaryTap != null) {
        recognizer.onSecondaryTap =
            () => widget.onLineSecondaryTap!(widget.lines[i].lineIndex);
      }
      _recognizers.add(recognizer);
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  bool _sameLineOrder(
    List<ContinuousReadingParagraphLine> oldLines,
    List<ContinuousReadingParagraphLine> newLines,
  ) {
    if (oldLines.length != newLines.length) {
      return false;
    }
    for (var i = 0; i < oldLines.length; i++) {
      if (oldLines[i].lineIndex != newLines[i].lineIndex) {
        return false;
      }
    }
    return true;
  }
}

class _VerseMarkerGrid extends StatelessWidget {
  static const minMarkerCellWidth = 14.0;
  static const markerWidthPerLetter = 10.0;
  static const markerColumnGap = 0.0;
  static const markerRowGap = 0.0;

  final _PositionedVerseMarkerGroup group;
  final TextStyle markerStyle;
  final ValueChanged<int> onMarkerTap;

  const _VerseMarkerGrid({
    required this.group,
    required this.markerStyle,
    required this.onMarkerTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rowsForMarkers(group.markers);
    final markerCellWidth = markerCellWidthForGroup(group);
    final maxColumns = rows
        .map((row) => row.length)
        .reduce((value, element) => value > element ? value : element);
    return SizedBox(
      width: maxColumns * markerCellWidth + (maxColumns - 1) * markerColumnGap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: EdgeInsets.only(
                bottom: identical(row, rows.last) ? 0 : markerRowGap,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: markerColumnGap),
                    _VerseMarkerText(
                      marker: row[i],
                      markerStyle: markerStyle,
                      width: markerCellWidth,
                      onTap: onMarkerTap,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<List<_VerseMarkerAnchor>> _rowsForMarkers(
    List<_VerseMarkerAnchor> markers,
  ) {
    final count = markers.length;
    final sizes = switch (count) {
      <= 0 => const <int>[],
      1 => const [1],
      2 => const [1, 1],
      3 => const [2, 1],
      4 => const [2, 2],
      5 => const [3, 2],
      _ => [
          for (var remaining = count; remaining > 0; remaining -= 3)
            remaining >= 3 ? 3 : remaining,
        ],
    };

    final rows = <List<_VerseMarkerAnchor>>[];
    var offset = 0;
    for (final size in sizes) {
      rows.add(markers.sublist(offset, offset + size));
      offset += size;
    }
    return rows;
  }

  static double markerCellWidthForGroup(_PositionedVerseMarkerGroup group) {
    final maxLetters = group.markers
        .map((marker) => marker.number.length)
        .reduce((value, element) => value > element ? value : element);
    return (maxLetters * markerWidthPerLetter)
        .clamp(minMarkerCellWidth, double.infinity)
        .toDouble();
  }
}

class _VerseMarkerText extends StatelessWidget {
  final _VerseMarkerAnchor marker;
  final TextStyle markerStyle;
  final double width;
  final ValueChanged<int> onTap;

  const _VerseMarkerText({
    required this.marker,
    required this.markerStyle,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(marker.lineIndex),
        child: Text(
          marker.number,
          style: markerStyle,
          textAlign: TextAlign.start,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

class _VerseMarkerAnchor {
  final String number;
  final int lineIndex;
  final int textOffset;

  const _VerseMarkerAnchor({
    required this.number,
    required this.lineIndex,
    required this.textOffset,
  });
}

class _VerseMarkerGroup {
  final double lineTop;
  final double lineHeight;
  final List<_VerseMarkerAnchor> markers;

  const _VerseMarkerGroup({
    required this.lineTop,
    required this.lineHeight,
    required this.markers,
  });

  _PositionedVerseMarkerGroup centered({required double markerGroupHeight}) {
    final top = lineTop + ((lineHeight - markerGroupHeight) / 2);
    return _PositionedVerseMarkerGroup(
      top: top,
      markers: markers,
    );
  }
}

class _PositionedVerseMarkerGroup {
  final double top;
  final List<_VerseMarkerAnchor> markers;

  const _PositionedVerseMarkerGroup({
    required this.top,
    required this.markers,
  });
}

class _VisualTextLine {
  final int start;
  final int end;
  final double top;
  final double height;

  const _VisualTextLine({
    required this.start,
    required this.end,
    required this.top,
    required this.height,
  });
}

List<InlineSpan> _nodesToSpans(
  List<dom.Node> nodes,
  TextStyle style,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_nodeToSpans(node, style));
  }
  return spans;
}

List<InlineSpan> _nodeToSpans(
  dom.Node node,
  TextStyle style,
) {
  if (node is dom.Text) {
    if (node.text.isEmpty) return const [];
    return [TextSpan(text: node.text, style: style)];
  }

  if (node is! dom.Element) {
    return const [];
  }

  if (node.localName == 'br') {
    return [TextSpan(text: '\n', style: style)];
  }

  final childStyle = _styleForElement(node, style);
  return _nodesToSpans(node.nodes, childStyle);
}

TextStyle _styleForElement(dom.Element element, TextStyle parentStyle) {
  var style = parentStyle;
  final localName = element.localName;

  if (localName == 'small') {
    style = style.copyWith(fontSize: (style.fontSize ?? 18) * 0.8);
  }
  if (localName == 'big') {
    style = style.copyWith(fontSize: (style.fontSize ?? 18) * 1.2);
  }
  final inlineFontSize = _inlineFontSize(element, style.fontSize ?? 18);
  if (inlineFontSize != null) {
    style = style.copyWith(fontSize: inlineFontSize);
  }
  if (localName == 'sup' ||
      element.classes.contains('footnote-marker-number')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * 0.75,
      fontStyle: FontStyle.italic,
    );
  }
  if (localName == 'i' ||
      localName == 'em' ||
      element.classes.contains('footnote') ||
      _hasFontStyle(element, 'italic')) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (localName == 'b' || localName == 'strong') {
    style = style.copyWith(fontWeight: FontWeight.bold);
  }

  return style;
}

double? _inlineFontSize(dom.Element element, double parentFontSize) {
  final inlineStyle = element.attributes['style'] ?? '';
  final match = RegExp(
    r'font-size\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(em|rem|px|%)?',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  if (match == null) return null;

  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return null;

  final unit = (match.group(2) ?? 'px').toLowerCase();
  return switch (unit) {
    'em' => parentFontSize * value,
    'rem' => parentFontSize * value,
    '%' => parentFontSize * value / 100,
    _ => value,
  };
}

bool _hasFontStyle(dom.Element element, String value) {
  final inlineStyle = element.attributes['style'] ?? '';
  return RegExp('font-style\\s*:\\s*$value', caseSensitive: false)
      .hasMatch(inlineStyle);
}

InlineSpan _withRecognizer(
  InlineSpan span,
  TapGestureRecognizer recognizer,
  TextStyle fallbackStyle,
) {
  if (span is! TextSpan) {
    return span;
  }

  return TextSpan(
    text: span.text,
    children: span.children
        ?.map((child) => _withRecognizer(child, recognizer, fallbackStyle))
        .toList(),
    style: span.style ?? fallbackStyle,
    recognizer: recognizer,
  );
}

int _plainTextLength(InlineSpan span) {
  if (span is! TextSpan) {
    return 0;
  }

  var length = span.text?.length ?? 0;
  final children = span.children;
  if (children != null) {
    for (final child in children) {
      length += _plainTextLength(child);
    }
  }
  return length;
}
