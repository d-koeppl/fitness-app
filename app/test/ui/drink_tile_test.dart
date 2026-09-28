// The beer tile at a phone's tile width: the label must read in full even
// with the system font size raised.
import 'package:fitness/ui/theme/palette.dart';
import 'package:fitness/ui/widgets/metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const tone = Tone(bg: Colors.orange, fill: Colors.orange, fg: Colors.brown, chip: Colors.white, icon: Colors.brown);

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the Beer label is not cut at text scale $scale', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                // (412dp phone − 2 × 16 gutter − 10 gap) / 2.
                child: SizedBox(
                  width: 185,
                  child: DrinkTile(
                    tone: tone,
                    count: 3,
                    volumeL: 0.5,
                    onAdd: () {},
                    onUndo: () {},
                    onSet: (_) {},
                    onOpenHistory: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (final text in ['Beer', '1.5 L']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
        final shown = tester.getRect(find.text(text));
        final tile = tester.getRect(find.byType(DrinkTile));
        expect(shown.right, lessThanOrEqualTo(tile.right), reason: text);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
