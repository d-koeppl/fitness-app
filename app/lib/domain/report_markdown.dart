// The minimal markdown the AI report and the coach are written in, ported
// from fitness-dashboard's web/lib/format.ts. Parsed here, without
// widgets, so it is tested on its own; lib/ui/rich_text.dart only turns the
// blocks into widgets.

/// One rendered block of the report body.
sealed class ReportBlock {
  const ReportBlock();
}

class HeadingBlock extends ReportBlock {
  const HeadingBlock(this.level, this.text);
  final int level;
  final String text;

  @override
  bool operator ==(Object other) => other is HeadingBlock && other.level == level && other.text == text;
  @override
  int get hashCode => Object.hash(level, text);
  @override
  String toString() => 'Heading($level, $text)';
}

class ListBlock extends ReportBlock {
  const ListBlock(this.items);
  final List<String> items;

  @override
  bool operator ==(Object other) => other is ListBlock && _listEq(other.items, items);
  @override
  int get hashCode => Object.hashAll(items);
  @override
  String toString() => 'List($items)';
}

class TableBlock extends ReportBlock {
  const TableBlock(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;

  @override
  bool operator ==(Object other) =>
      other is TableBlock &&
      _listEq(other.headers, headers) &&
      other.rows.length == rows.length &&
      [for (var i = 0; i < rows.length; i++) _listEq(other.rows[i], rows[i])].every((e) => e);
  @override
  int get hashCode => Object.hash(Object.hashAll(headers), rows.length);
  @override
  String toString() => 'Table($headers, $rows)';
}

class MermaidBlock extends ReportBlock {
  const MermaidBlock(this.code);
  final String code;

  @override
  bool operator ==(Object other) => other is MermaidBlock && other.code == code;
  @override
  int get hashCode => code.hashCode;
  @override
  String toString() => 'Mermaid($code)';
}

/// A ```chart block: the coach's chart as JSON (ADR-035), drawn by
/// ui/charts/coach_chart.dart. Kept as source here; lib/domain/coach_chart.dart
/// parses it.
class ChartBlock extends ReportBlock {
  const ChartBlock(this.source);
  final String source;

  @override
  bool operator ==(Object other) => other is ChartBlock && other.source == source;
  @override
  int get hashCode => source.hashCode;
  @override
  String toString() => 'Chart($source)';
}

class CodeBlock extends ReportBlock {
  const CodeBlock(this.code, [this.lang]);
  final String code;
  final String? lang;

  @override
  bool operator ==(Object other) => other is CodeBlock && other.code == code && other.lang == lang;
  @override
  int get hashCode => Object.hash(code, lang);
  @override
  String toString() => 'Code($lang, $code)';
}

class ParagraphBlock extends ReportBlock {
  const ParagraphBlock(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is ParagraphBlock && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'Paragraph($text)';
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// A fenced code block: ```chart, ```mermaid, ```, or ```<any other language>.
final _fence = RegExp(r'^ {0,3}```\s*(\S*)\s*$');
final _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$');
final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
final _tableSeparatorCell = RegExp(r'^:?-+:?$');
// A thematic break ("---", "* * *"). Never matches a bullet, which needs
// whitespace after a single marker.
final _hr = RegExp(r'^ {0,3}([-*_])\s*(?:\1\s*){2,}$');

List<String> _splitTableRow(String line) {
  final trimmed = line.trim().replaceFirst(RegExp(r'^\|'), '').replaceFirst(RegExp(r'\|$'), '');
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

bool _isTableSeparator(String line) {
  if (!line.contains('|') && !line.contains('-')) return false;
  final cells = _splitTableRow(line);
  return cells.isNotEmpty && cells.every(_tableSeparatorCell.hasMatch);
}

/// Splits the report body into blocks.
///
/// Line-driven rather than blank-line-driven: Gemini writes its
/// "### Recommendations" heading and the bullets under it with no blank
/// line between them.
List<ReportBlock> parseReportBlocks(String md) {
  final blocks = <ReportBlock>[];
  var paragraph = <String>[];
  List<String>? items;

  void flush() {
    if (paragraph.isNotEmpty) blocks.add(ParagraphBlock(paragraph.join(' ')));
    if (items != null && items!.isNotEmpty) blocks.add(ListBlock(items!));
    paragraph = [];
    items = null;
  }

  final rawLines = md.trim().split('\n');
  for (var i = 0; i < rawLines.length; i++) {
    final fence = _fence.firstMatch(rawLines[i]);
    if (fence != null) {
      flush();
      final lang = fence.group(1)!.toLowerCase();
      final code = <String>[];
      i++;
      while (i < rawLines.length && !_fence.hasMatch(rawLines[i])) {
        code.add(rawLines[i]);
        i++;
      }
      final body = code.join('\n');
      blocks.add(switch (lang) {
        'chart' => ChartBlock(body),
        // Only in chats from the web app: the coach is no longer asked for
        // Mermaid, and nothing here draws it (ADR-035).
        'mermaid' => MermaidBlock(body),
        _ => CodeBlock(body, lang.isEmpty ? null : lang),
      });
      continue;
    }

    final line = rawLines[i];
    if (line.trim().isEmpty) {
      flush();
      continue;
    }

    if (_hr.hasMatch(line)) {
      flush();
      continue;
    }

    if (line.contains('|') && i + 1 < rawLines.length && _isTableSeparator(rawLines[i + 1])) {
      flush();
      final headers = _splitTableRow(line);
      final rows = <List<String>>[];
      i += 2;
      while (i < rawLines.length &&
          rawLines[i].trim().isNotEmpty &&
          rawLines[i].contains('|') &&
          !_fence.hasMatch(rawLines[i])) {
        rows.add(_splitTableRow(rawLines[i]));
        i++;
      }
      i--; // the loop's own i++ steps back onto the line that ended the table
      blocks.add(TableBlock(headers, rows));
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flush();
      final text = heading.group(2)!.replaceFirst(RegExp(r'\s*#+\s*$'), '').trim();
      if (text.isNotEmpty) blocks.add(HeadingBlock(heading.group(1)!.length, text));
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      if (items == null) {
        flush();
        items = [];
      }
      items!.add(bullet.group(1)!.trim());
      continue;
    }

    // A wrapped continuation of the bullet above, or paragraph text.
    if (items != null && items!.isNotEmpty) {
      items![items!.length - 1] += ' ${line.trim()}';
    } else {
      paragraph.add(line.trim());
    }
  }

  flush();
  return blocks;
}

/// One run of inline text and how it is emphasised — or, for [math], raw
/// LaTeX.
class InlineRun {
  const InlineRun(this.text, {this.bold = false, this.italic = false, this.math = false, this.display = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool math;
  final bool display;

  @override
  bool operator ==(Object other) =>
      other is InlineRun &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.math == math &&
      other.display == display;
  @override
  int get hashCode => Object.hash(text, bold, italic, math, display);
  @override
  String toString() =>
      'InlineRun($text${bold ? ', bold' : ''}${italic ? ', italic' : ''}'
      '${math ? ', math' : ''}${display ? ', display' : ''})';
}

// `$$…$$` before `$…$` before `**bold**` before `*italic*`. Math and
// italics stop at a newline, so an unmatched marker stays literal.
final _inline = RegExp(r'(\$\$[^$\n]+?\$\$|\$[^$\n]+?\$|\*\*[^*]+\*\*|\*[^*\n]+\*)');

// A backslash command that escaped a $...$ span, swapped for its character.
final _latexFallback = <(RegExp, String)>[
  (RegExp(r'\\rightarrow'), '→'),
  (RegExp(r'\\to(?=\s|$)'), '→'),
  (RegExp(r'\\times'), '×'),
  (RegExp(r'\\approx'), '≈'),
  (RegExp(r'\\ge(?=\s|$)'), '≥'),
  (RegExp(r'\\le(?=\s|$)'), '≤'),
  (RegExp(r'\\cdot'), '·'),
];

/// Splits a line into plain, bold, italic and math runs.
List<InlineRun> parseInline(String text) {
  // String.split with a capturing group, as JavaScript does it: the
  // matches stay in the result, between the text around them.
  final chunks = <String>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    chunks
      ..add(text.substring(last, m.start))
      ..add(m.group(0)!);
    last = m.end;
  }
  chunks.add(text.substring(last));

  return chunks.where((chunk) => chunk.isNotEmpty).map((chunk) {
    if (chunk.startsWith(r'$$') && chunk.endsWith(r'$$') && chunk.length > 4) {
      return InlineRun(chunk.substring(2, chunk.length - 2), math: true, display: true);
    }
    if (chunk.startsWith(r'$') && chunk.endsWith(r'$') && chunk.length > 2) {
      return InlineRun(chunk.substring(1, chunk.length - 1), math: true);
    }
    if (chunk.startsWith('**') && chunk.endsWith('**') && chunk.length > 4) {
      return InlineRun(chunk.substring(2, chunk.length - 2), bold: true);
    }
    if (chunk.startsWith('*') && chunk.endsWith('*') && chunk.length > 2) {
      return InlineRun(chunk.substring(1, chunk.length - 1), italic: true);
    }
    var plain = chunk;
    for (final (pattern, replacement) in _latexFallback) {
      plain = plain.replaceAll(pattern, replacement);
    }
    return InlineRun(plain);
  }).toList();
}
