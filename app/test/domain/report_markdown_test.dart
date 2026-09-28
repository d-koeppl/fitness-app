// Ported from the parseInline and parseReportBlocks cases of
// fitness-dashboard's web/lib/format.test.ts.
import 'package:fitness/domain/report_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInline', () {
    test('leaves plain text alone', () {
      expect(parseInline('Your HRV is up.'), [const InlineRun('Your HRV is up.')]);
    });

    test('pulls out a bold run', () {
      expect(parseInline('Form is **-11.3** today'), [
        const InlineRun('Form is '),
        const InlineRun('-11.3', bold: true),
        const InlineRun(' today'),
      ]);
    });

    test('pulls out an italic run', () {
      expect(parseInline('*Missing data: sleep*'), [const InlineRun('Missing data: sleep', italic: true)]);
    });

    test('does not read a bold run as two italic ones', () {
      expect(parseInline('**247**'), [const InlineRun('247', bold: true)]);
    });

    test('handles bold and italic in the same line', () {
      expect(parseInline('**Verdict:** be *careful*'), [
        const InlineRun('Verdict:', bold: true),
        const InlineRun(' be '),
        const InlineRun('careful', italic: true),
      ]);
    });

    test('leaves a lone asterisk literal', () {
      expect(parseInline('2 * 3 is six'), [const InlineRun('2 * 3 is six')]);
    });

    test('does not run an italic across a line break', () {
      expect(parseInline('a *b\nc* d'), [const InlineRun('a *b\nc* d')]);
    });

    test('leaves empty markers alone rather than emitting a blank span', () {
      expect(parseInline('**'), [const InlineRun('**')]);
    });

    test('pulls out an inline math span, keeping the LaTeX', () {
      expect(parseInline(r'Where $FTP = 0.95 \times MMP$ holds'), [
        const InlineRun('Where '),
        const InlineRun(r'FTP = 0.95 \times MMP', math: true),
        const InlineRun(' holds'),
      ]);
    });

    test(r'reads $$...$$ as display math rather than two inline spans', () {
      expect(parseInline(r'$$x^2$$'), [const InlineRun('x^2', math: true, display: true)]);
    });

    test('swaps a bare backslash command for its plain character outside any math', () {
      expect(parseInline(r'climbed 0 \rightarrow 13.9 in July'), [const InlineRun('climbed 0 → 13.9 in July')]);
    });
  });

  group('parseReportBlocks', () {
    test('keeps a heading and the bullets under it apart without a blank line', () {
      expect(
        parseReportBlocks(
          'Keep movement light today.\n\n### Recommendations\n* **Active Movement:** a brisk walk.\n* **Sleep Hygiene:** above 7.5 hours.',
        ),
        [
          const ParagraphBlock('Keep movement light today.'),
          const HeadingBlock(3, 'Recommendations'),
          const ListBlock(['**Active Movement:** a brisk walk.', '**Sleep Hygiene:** above 7.5 hours.']),
        ],
      );
    });

    test('joins the lines of a wrapped paragraph', () {
      expect(parseReportBlocks('Your HRV is up\nand your resting HR is down.'), [
        const ParagraphBlock('Your HRV is up and your resting HR is down.'),
      ]);
    });

    test("hangs a wrapped bullet's continuation on the bullet above it", () {
      expect(parseReportBlocks('- Walk today,\n  not a session.\n- Sleep 7.5 hours.'), [
        const ListBlock(['Walk today, not a session.', 'Sleep 7.5 hours.']),
      ]);
    });

    test('does not read a bold run at the start of a line as a bullet', () {
      expect(parseReportBlocks('**Form:** -15.6, in the productive zone.'), [
        const ParagraphBlock('**Form:** -15.6, in the productive zone.'),
      ]);
    });

    test('trims a closing run of hashes off a heading', () {
      expect(parseReportBlocks('## Recovery ##'), [const HeadingBlock(2, 'Recovery')]);
    });

    test('returns nothing for an empty body', () {
      expect(parseReportBlocks('   \n\n '), isEmpty);
    });

    test('drops a thematic break instead of showing it as text', () {
      expect(parseReportBlocks('Above the line.\n\n---\n\nBelow the line.'), [
        const ParagraphBlock('Above the line.'),
        const ParagraphBlock('Below the line.'),
      ]);
    });

    test('reads a markdown table into headers and rows', () {
      expect(
        parseReportBlocks(
          'Before.\n\n| Week | Fitness | Form |\n|---|---|---|\n| Aug 25 | 38.3 | -12 |\n| Sep 1 | 46.0 | -4 |\n\nAfter.',
        ),
        [
          const ParagraphBlock('Before.'),
          const TableBlock(
            ['Week', 'Fitness', 'Form'],
            [
              ['Aug 25', '38.3', '-12'],
              ['Sep 1', '46.0', '-4'],
            ],
          ),
          const ParagraphBlock('After.'),
        ],
      );
    });

    test('tolerates alignment colons and no outer pipes in the separator row', () {
      expect(parseReportBlocks('Week | Fitness\n:---|---:\nAug 25 | 38.3'), [
        const TableBlock(
          ['Week', 'Fitness'],
          [
            ['Aug 25', '38.3'],
          ],
        ),
      ]);
    });

    test('does not mistake a stray pipe in a sentence for a table', () {
      expect(parseReportBlocks('Rest | recover, in that order.'), [
        const ParagraphBlock('Rest | recover, in that order.'),
      ]);
    });

    test('pulls a fenced mermaid block out as its own block', () {
      expect(parseReportBlocks('Trend below.\n\n```mermaid\nxychart-beta\nline [10, 20, 30]\n```\n\nDone.'), [
        const ParagraphBlock('Trend below.'),
        const MermaidBlock('xychart-beta\nline [10, 20, 30]'),
        const ParagraphBlock('Done.'),
      ]);
    });

    test('treats any other fenced block as code, not a paragraph to rewrap', () {
      expect(parseReportBlocks('```\nweek1 -> week2\n```'), [const CodeBlock('week1 -> week2')]);
      expect(parseReportBlocks('```json\n{"a": 1}\n```'), [const CodeBlock('{"a": 1}', 'json')]);
    });

    test('does not let table detection reach inside a fence', () {
      expect(parseReportBlocks('```mermaid\npie title \$ spent\n"A" : 10\n```'), [
        const MermaidBlock('pie title \$ spent\n"A" : 10'),
      ]);
    });

    test('keeps a math span intact as paragraph text', () {
      expect(parseReportBlocks(r'Fitness climbed $0 \rightarrow 13.9$ today.'), [
        const ParagraphBlock(r'Fitness climbed $0 \rightarrow 13.9$ today.'),
      ]);
    });
  });
}
