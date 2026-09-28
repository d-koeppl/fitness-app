// The report's markdown as widgets — the rendering half of
// fitness-dashboard's RichText (web/components/ui.tsx). Parsing lives in
// lib/domain/report_markdown.dart.
//
// Math is real LaTeX (flutter_math_fork), as KaTeX drew it on the web; a
// formula it cannot parse falls back to its source in a monospace run, as
// it shows while the browser build fetches the KaTeX fonts on first use
// (katex_fonts.dart). The
// coach's ```chart blocks are drawn by ui/charts/coach_chart.dart (ADR-035).
// Mermaid, which the web drew, only survives in chats written there, and is
// shown as its source under a line saying so.

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../domain/report_markdown.dart';
import '../charts/coach_chart.dart';
import '../theme/palette.dart';
import 'katex_fonts.dart';

class ReportText extends StatelessWidget {
  const ReportText(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant);

    Widget math(InlineRun run, TextStyle base) {
      final source = Text(run.text, style: base.copyWith(fontFamily: 'monospace'));
      Widget tex() => Math.tex(
        run.text,
        mathStyle: run.display ? MathStyle.display : MathStyle.text,
        textStyle: base.copyWith(color: p.onSurface),
        onErrorFallback: (_) => source,
      );
      if (katexFontsReady) return tex();
      return FutureBuilder(
        future: loadKatexFonts(),
        builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done ? tex() : source,
      );
    }

    TextSpan inline(String text, TextStyle base) => TextSpan(
      style: base,
      children: [
        for (final run in parseInline(text))
          run.math
              ? WidgetSpan(alignment: PlaceholderAlignment.middle, child: math(run, base))
              : TextSpan(
                  text: run.text,
                  style: run.bold
                      ? TextStyle(fontWeight: FontWeight.w700, color: p.onSurface)
                      : run.italic
                      ? const TextStyle(fontStyle: FontStyle.italic)
                      : null,
                ),
      ],
    );

    // A paragraph that is one `$$...$$` formula is a block of its own,
    // centred and scrolling sideways rather than wrapping mid-formula.
    Widget paragraph(String text) {
      final runs = parseInline(text);
      if (runs.length == 1 && runs.single.math && runs.single.display) {
        return Center(
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: math(runs.single, body)),
        );
      }
      return Text.rich(inline(text, body));
    }

    Widget codeBox(String source) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      // Bordered, like a table: inside a coach reply the bubble is this
      // same colour, and the box would vanish into it.
      decoration: BoxDecoration(
        color: p.surfaceContainerHigh,
        border: Border.all(color: p.outlineVariant),
        borderRadius: BorderRadius.circular(Shape.lg),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          source,
          style: TypeScale.bodyMedium.copyWith(color: p.onSurface, fontFamily: 'monospace'),
        ),
      ),
    );

    final blocks = parseReportBlocks(markdown);
    final children = <Widget>[];
    for (final block in blocks) {
      children.add(switch (block) {
        HeadingBlock(:final level, :final text) => Text.rich(
          inline(text, (level <= 2 ? TypeScale.titleLarge : TypeScale.titleMedium).copyWith(color: p.onSurface)),
        ),
        ParagraphBlock(:final text) => paragraph(text),
        ListBlock(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 10, right: 8),
                      decoration: BoxDecoration(color: p.outline, shape: BoxShape.circle),
                    ),
                    Expanded(child: Text.rich(inline(item, body))),
                  ],
                ),
              ),
          ],
        ),
        TableBlock(:final headers, :final rows) => _Table(headers: headers, rows: rows, cell: inline),
        ChartBlock(:final source) => CoachChartView(source: source, fallback: codeBox),
        MermaidBlock(:final code) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A diagram from the web app, which this app does not draw:',
              style: TypeScale.labelMedium.copyWith(color: p.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            codeBox(code),
          ],
        ),
        CodeBlock(:final code) => codeBox(code),
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, child) in children.indexed) ...[
          // Headings sit 8 px closer to what follows them, as on the web.
          if (i > 0) SizedBox(height: blocks[i - 1] is HeadingBlock ? 8 : 16),
          child,
        ],
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.headers, required this.rows, required this.cell});

  final List<String> headers;
  final List<List<String>> rows;
  final TextSpan Function(String text, TextStyle base) cell;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final border = BorderSide(color: p.outlineVariant);
    return Container(
      decoration: BoxDecoration(border: Border.fromBorderSide(border), borderRadius: BorderRadius.circular(Shape.md)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: p.surfaceContainerHigh,
                border: Border(bottom: border),
              ),
              children: [
                for (final h in headers)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text.rich(cell(h, TypeScale.labelLarge.copyWith(color: p.onSurface))),
                  ),
              ],
            ),
            for (final (i, row) in rows.indexed)
              TableRow(
                decoration: i < rows.length - 1 ? BoxDecoration(border: Border(bottom: border)) : null,
                children: [
                  for (var c = 0; c < headers.length; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text.rich(
                        cell(c < row.length ? row[c] : '', TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
