// The report's markdown as widgets — the rendering half of
// fitness-dashboard's RichText (web/components/ui.tsx). Parsing lives in
// lib/domain/report_markdown.dart.
//
// Not yet ported: KaTeX math and Mermaid diagrams (phase 7, where the coach
// is what writes them). Until then a math span shows its LaTeX in a
// monospace run and a diagram shows its source as a code block.

import 'package:flutter/material.dart';

import '../../domain/report_markdown.dart';
import '../theme/palette.dart';

class ReportText extends StatelessWidget {
  const ReportText(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final body = TypeScale.bodyLarge.copyWith(color: p.onSurfaceVariant);

    TextSpan inline(String text, TextStyle base) => TextSpan(
      style: base,
      children: [
        for (final run in parseInline(text))
          TextSpan(
            text: run.text,
            style: run.math
                ? const TextStyle(fontFamily: 'monospace')
                : run.bold
                ? TextStyle(fontWeight: FontWeight.w700, color: p.onSurface)
                : run.italic
                ? const TextStyle(fontStyle: FontStyle.italic)
                : null,
          ),
      ],
    );

    Widget codeBox(String source) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surfaceContainerHigh, borderRadius: BorderRadius.circular(Shape.lg)),
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
        ParagraphBlock(:final text) => Text.rich(inline(text, body)),
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
        MermaidBlock(:final code) => codeBox(code),
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
