// Small shared chrome — ported from fitness-dashboard's web/components/ui.tsx:
// section headers, notices, the connect card and the segmented control.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/palette.dart';

/// A rounded card on the page's surface colour.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.radius = Shape.xl});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // A Material rather than a decorated box, so a row inside that is
    // tappable shows its ripple on the card rather than under it.
    return Material(
      color: Palette.of(context).surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TypeScale.titleLarge.copyWith(color: Palette.of(context).onSurface)),
          ),
          ?action,
        ],
      ),
    );
  }
}

enum NoticeTone { info, error }

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = NoticeTone.info});

  final String text;
  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (bg, fg) = tone == NoticeTone.error
        ? (p.error.container, p.error.onContainer)
        : (p.surface, p.onSurfaceVariant);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Shape.lg)),
      child: Text(text, style: TypeScale.bodyMedium.copyWith(color: fg)),
    );
  }
}

/// "Connect Google Health to …" with a Connect button. The button asks the
/// API for the consent URL (it needs the ID token) and opens it in a
/// browser; the grant lands on the API's callback, and the next refresh
/// shows it.
class ConnectCard extends StatefulWidget {
  const ConnectCard({super.key, required this.text, required this.consentUrl});

  final String text;
  final Future<String> Function() consentUrl;

  @override
  State<ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<ConnectCard> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final url = await widget.consentUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the Google sign-in')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      radius: Shape.lg,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(widget.text, style: TypeScale.bodyMedium.copyWith(color: p.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
        ],
      ),
    );
  }
}

/// The pill-group selector: the Fitness tab's sections and the Health tab's
/// range, at two densities.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.dense = false,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) label;
  final ValueChanged<T> onSelect;

  /// Smaller labels sized to their text, rather than splitting the row.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget pill(T option) {
      final isSelected = option == selected;
      final text = Text(
        label(option),
        textAlign: TextAlign.center,
        style: (dense ? TypeScale.labelMedium : TypeScale.labelLarge).copyWith(
          color: isSelected ? p.secondary.onContainer : p.onSurfaceVariant,
        ),
      );
      return Material(
        color: isSelected ? p.secondary.container : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => onSelect(option),
          child: Padding(
            padding: dense
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                : const EdgeInsets.symmetric(vertical: 8),
            child: text,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(color: p.surface, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: dense ? MainAxisSize.min : MainAxisSize.max,
        children: [
          for (final (i, option) in options.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            dense ? pill(option) : Expanded(child: pill(option)),
          ],
        ],
      ),
    );
  }
}

/// The W / D / L disc a match leads with, in its outcome's tone.
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge({super.key, required this.letter, this.size = 42});

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = Palette.of(context).outcomeTone(letter);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tone.fg),
      ),
    );
  }
}

/// A round icon disc, as the list rows lead with.
class IconDisc extends StatelessWidget {
  const IconDisc({
    super.key,
    required this.icon,
    required this.background,
    required this.color,
    this.size = 42,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color background;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
